// Live tracking (CLAUDE.md section 23.3): fused positions from `gps:update` (bus GpsUpdated) -> memory + live_positions,
// pushed as `tracking:positions` to admins (everyone) and each zone's supervisors (own zone), at most once a second.
// The crisis engine keeps its own crisis:positions; nothing here touches it.
import { Router } from 'express';
import mongoose from 'mongoose';
import { z } from 'zod';
import { authenticate, requireRole } from '../../core/auth.js';
import { AppError, asyncHandler } from '../../core/errors.js';
import { validate, objectId } from '../../core/validate.js';
import { subscribe } from '../../core/bus.js';
import { emitTo } from '../../core/socket.js';
import { logger } from '../../core/logger.js';
import { env } from '../../config/env.js';
import { User } from '../../models/User.js';
import { parseOrs, planEmits, presenceChanges, snapshotScope, toWire } from './tracking.logic.js';

const EMIT_MS = 1000;
const SWEEP_MS = 5000;
const USER_TTL_MS = 60_000;

const staleSec = () => env.TRACKING_STALE_SEC ?? 30;
const offlineSec = () => env.TRACKING_OFFLINE_SEC ?? 120;
const col = () => mongoose.connection.collection('live_positions');

/** userId -> entry (memory is authoritative while running; live_positions survives restarts). */
const live = new Map();
const dirty = new Set();
const lastPresence = new Map();
const userCache = new Map();

async function who(userId) {
  const hit = userCache.get(userId);
  if (hit && Date.now() - hit.at < USER_TTL_MS) return hit.u;
  const u = await User.findById(userId).select('fullName employeeId role zoneId status');
  const v = u ? { name: u.fullName, employeeId: u.employeeId, role: u.role, zoneId: u.zoneId ? String(u.zoneId) : null } : null;
  userCache.set(userId, { u: v, at: Date.now() });
  return v;
}

export async function onGps(d) {
  if (env.TRACKING_ENABLED === false) return;
  const u = await who(String(d.userId));
  if (!u || u.role === 'admin') return; // admins are viewers, not tracked
  const prev = live.get(String(d.userId));
  if (prev && new Date(prev.ts) > new Date(d.ts)) return; // out-of-order (outbox replay): keep the newer fix
  const e = { userId: String(d.userId), ...u, lat: d.lat, lng: d.lng, accuracyM: d.accuracyM, headingDeg: d.headingDeg ?? null, speedMps: d.speedMps ?? null, source: d.source ?? 'GPS', tunnelId: d.tunnelId ?? null, sosId: d.sosId ?? null, ts: d.ts };
  live.set(e.userId, e);
  dirty.add(e.userId);
  col()
    .updateOne({ userId: e.userId }, { $set: { ...e, ts: new Date(e.ts), updatedAt: new Date() } }, { upsert: true })
    .catch((err) => logger.warn({ err: err.message }, 'live_positions write failed'));
}

function flush(now = Date.now()) {
  if (!dirty.size) return;
  const entries = [...dirty].map((id) => live.get(id)).filter(Boolean);
  dirty.clear();
  for (const { room, positions } of planEmits(entries, now, staleSec(), offlineSec())) emitTo([room], 'tracking:positions', { positions });
}

function sweep(now = Date.now()) {
  for (const id of presenceChanges([...live.values()], lastPresence, now, staleSec(), offlineSec())) dirty.add(id);
}

async function restore() {
  try {
    const since = new Date(Date.now() - 12 * 3600 * 1000);
    for (const r of await col().find({ ts: { $gte: since } }).toArray()) {
      live.set(String(r.userId), { ...r, userId: String(r.userId), ts: new Date(r.ts).toISOString() });
    }
  } catch (err) {
    logger.warn({ err: err.message }, 'live_positions restore failed');
  }
}

const router = Router();

router.get(
  '/live',
  authenticate(),
  requireRole('supervisor', 'admin'),
  validate({ query: z.object({ zoneId: objectId.optional() }) }),
  asyncHandler(async (req, res) => {
    const scope = snapshotScope(req.user, req.query.zoneId);
    if (scope.error) throw new AppError(403, scope.error, 'This zone is outside your scope');
    const now = Date.now();
    const positions = [...live.values()].filter((e) => !scope.zoneId || e.zoneId === scope.zoneId).map((e) => toWire(e, now, staleSec(), offlineSec()));
    res.json({ positions, staleSec: staleSec(), offlineSec: offlineSec(), enabled: env.TRACKING_ENABLED !== false });
  }),
);

const ll = z.coerce.number();
router.get(
  '/surface-route',
  authenticate(),
  validate({ query: z.object({ fromLat: ll.min(-90).max(90), fromLng: ll.min(-180).max(180), toLat: ll.min(-90).max(90), toLng: ll.min(-180).max(180) }) }),
  asyncHandler(async (req, res) => {
    if (!env.ORS_API_KEY) throw new AppError(503, 'ROUTING_NOT_CONFIGURED', 'Set ORS_API_KEY in backend/.env for surface routes');
    const q = req.query;
    const url = `https://api.openrouteservice.org/v2/directions/foot-walking?start=${q.fromLng},${q.fromLat}&end=${q.toLng},${q.toLat}`;
    let r;
    try {
      r = await fetch(url, { headers: { Authorization: env.ORS_API_KEY, Accept: 'application/geo+json' }, signal: AbortSignal.timeout(8000) });
    } catch {
      throw new AppError(502, 'ROUTING_FAILED', 'OpenRouteService did not answer');
    }
    const route = r.ok ? parseOrs(await r.json().catch(() => null)) : null;
    if (!route) throw new AppError(502, 'ROUTING_FAILED', `OpenRouteService returned ${r.status}`);
    res.json(route);
  }),
);

let timers = [];
async function init() {
  await restore();
  subscribe('GpsUpdated', async ({ data }) => onGps(data));
  timers = [setInterval(() => flush(), EMIT_MS), setInterval(() => sweep(), SWEEP_MS)];
  for (const t of timers) t.unref?.();
}

export default { name: 'tracking', basePath: '/api/tracking', router, init };
