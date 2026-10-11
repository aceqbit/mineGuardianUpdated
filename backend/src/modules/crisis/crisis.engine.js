import mongoose from 'mongoose';
import { env } from '../../config/env.js';
import { AppError } from '../../core/errors.js';
import { audit } from '../../core/audit.js';
import { bus } from '../../core/bus.js';
import { sendToUsers } from '../../core/fcm.js';
import { haversineM } from '../../core/geo.js';
import { logger } from '../../core/logger.js';
import { emitTo } from '../../core/socket.js';
import { makeCall, sendSms } from '../../core/twilio.js';
import { Crisis } from '../../models/Crisis.js';
import { CrisisReport } from '../../models/CrisisReport.js';
import { GpsPing } from '../../models/GpsPing.js';
import { SosEvent } from '../../models/SosEvent.js';
import { User } from '../../models/User.js';
import { Zone } from '../../models/Zone.js';
import { uploadBuffer, signedUrl } from '../../core/storage.js';
import { accountedCounts, buildRoster, crisisTexts, mergeTrigger, newShareToken, setAccounted, validateResolve } from './crisis.logic.js';
import { buildCrisisReportPdf } from './crisis.report.js';

const POSITION_THROTTLE_MS = 2000;
const PING_FLUSH_MS = 15_000;
const TIMELINE_FLUSH_MS = 5_000;
const MOVE_RECOMPUTE_M = 10;
const RECOMPUTE_DEBOUNCE_MS = 3000;

/** Memory is authoritative while a crisis is ACTIVE; Mongo is written behind it. */
const S = { crisis: null, activating: null, positions: new Map(), pings: [], timeline: [], routes: null, timers: [], lastPosEmit: 0, posTimer: null, recomputeTimer: null, routedAt: new Map() };

export const getActive = () => S.crisis;
export const getPositions = () => S.positions;
export const getRoutes = () => S.routes;

const staffRooms = (zoneIds) => ['role:admin', ...zoneIds.map((z) => `zone:${z}:supervisors`)];

async function recipients(zoneIds) {
  const [sups, admins] = await Promise.all([
    User.find({ role: 'supervisor', zoneId: { $in: zoneIds }, status: 'active' }),
    User.find({ role: 'admin', status: 'active' }),
  ]);
  return [...sups, ...admins];
}

/** Calls + SMS + FCM. Every leg is independent and none of it blocks anything. */
async function blast(crisis) {
  const zones = await Zone.find({ _id: { $in: crisis.zoneIds } });
  const people = await recipients(crisis.zoneIds);
  const trackUrl = `${env.PUBLIC_BASE_URL}/public/track/${crisis.shareToken}`;
  const { voice, sms } = crisisTexts({ reason: crisis.reason, zoneCodes: zones.map((z) => z.code), trackUrl });
  const results = await Promise.allSettled([
    // Calls and texts need an optional contact number; everyone is still reached by push and the app.
    ...people.filter((p) => p.phone?.e164).flatMap((p) => [makeCall(p.phone.e164, voice), sendSms(p.phone.e164, sms)]),
    sendToUsers(people.map((p) => String(p._id)), { title: 'EMERGENCY — crisis mode', body: crisis.reason || 'A crisis has been declared', data: { type: 'crisis', crisisId: String(crisis._id) } }),
  ]);
  logger.info(`crisis blast: ${results.filter((r) => r.status === 'fulfilled').length}/${results.length} legs settled`);
}

function note(text) {
  S.timeline.push({ at: new Date(), text });
}

async function flushTimeline() {
  if (!S.crisis || !S.timeline.length) return;
  const batch = S.timeline.splice(0);
  await Crisis.updateOne({ _id: S.crisis._id }, { $push: { timeline: { $each: batch } } }).catch((err) => {
    S.timeline.unshift(...batch);
    logger.warn({ err: err.message }, 'crisis timeline flush failed');
  });
}

async function flushPings() {
  if (!S.pings.length) return;
  const batch = S.pings.splice(0);
  await GpsPing.insertMany(batch, { ordered: false }).catch((err) => logger.warn({ err: err.message }, 'gps ping flush failed'));
}

/** Everything a client needs. Never includes the share token (admins read it via GET /active). */
const publicView = (c) => ({ crisisId: String(c._id), startedAt: c.startedAt, trigger: c.trigger, triggers: c.triggers, zoneIds: c.zoneIds.map(String), reason: c.reason, sosIds: (c.sosIds ?? []).map(String) });

export async function activate({ trigger, zoneIds, reason = '', actor = null, sosId = null }) {
  // Two triggers arriving together must merge, never create two crises.
  if (S.activating) await S.activating.catch(() => null);
  if (S.crisis) return merge(trigger, zoneIds, reason, sosId);
  let release;
  S.activating = new Promise((r) => { release = r; });
  try {
    const _id = new mongoose.Types.ObjectId();
    const now = new Date();
    const crisis = {
      _id, status: 'ACTIVE', startedAt: now, trigger: { ...trigger, at: now }, triggers: [{ ...trigger, at: now }], zoneIds: [...new Set(zoneIds.map(String))],
      reason, sosIds: sosId ? [sosId] : [], shareToken: newShareToken(), timeline: [{ at: now, text: `Crisis activated by ${trigger.type}${reason ? ` — ${reason}` : ''}` }], accounted: [], blockedEdgeIds: [],
    };
    S.crisis = crisis;
    S.positions = new Map();
    S.routes = null;
    // 1. blast first: every connected client hears about it before anything touches the database
    emitTo(['*'], 'crisis:activated', publicView(crisis));
    bus.publish('CrisisActivated', { crisisId: String(_id), zoneIds: crisis.zoneIds });
    // 2. notifications (calls, SMS, push) start before anything touches the database and never block it
    blast(crisis).catch((err) => logger.warn({ err: err.message }, 'crisis blast failed'));
    // 3. persist after
    await Crisis.create(crisis);
    audit(actor, 'CRISIS_ACTIVATED', 'crisis', _id, { trigger: trigger.type }).catch(() => null);
    // 4. routes, if the rerouter exists
    recompute('activation').catch(() => null);
    return crisis;
  } finally {
    release();
    S.activating = null;
  }
}

async function merge(trigger, zoneIds, reason, sosId) {
  const { crisis, changed, line } = mergeTrigger(S.crisis, trigger, zoneIds, reason);
  if (sosId && !(crisis.sosIds ?? []).map(String).includes(String(sosId))) crisis.sosIds = [...(crisis.sosIds ?? []), sosId];
  if (!changed && !sosId) return S.crisis;
  S.crisis = crisis;
  if (line) S.timeline.push(line);
  await Crisis.updateOne({ _id: crisis._id }, { $set: { triggers: crisis.triggers, zoneIds: crisis.zoneIds, sosIds: crisis.sosIds } }).catch((err) => logger.warn({ err: err.message }, 'crisis merge persist failed'));
  emitTo(['*'], 'crisis:updated', { ...publicView(crisis), line });
  if (changed) recompute('merge').catch(() => null);
  return crisis;
}

export async function activateFromSos(sosId) {
  const sos = await SosEvent.findById(sosId);
  if (!sos || sos.status !== 'ACTIVE') return null;
  const worker = await User.findById(sos.workerId).select('fullName');
  const crisis = await activate({ trigger: { type: 'SOS', refId: String(sos._id) }, zoneIds: [String(sos.zoneId)], reason: `SOS from ${worker?.fullName ?? 'a worker'}`, sosId: sos._id });
  await SosEvent.updateOne({ _id: sos._id }, { $set: { crisisId: crisis._id } });
  if (sos.location?.coordinates) {
    const [lng, lat] = sos.location.coordinates;
    S.positions.set(String(sos.workerId), { userId: String(sos.workerId), name: worker?.fullName ?? '', zoneId: String(sos.zoneId), lat, lng, accuracyM: sos.accuracyM ?? null, ts: (sos.triggeredAt ?? new Date()).toISOString(), sosId: String(sos._id) });
    recompute('sos position').catch(() => null);
  }
  return crisis;
}

/** SosCancelled -> that worker is SAFE. */
export async function onSosCancelled(sosId) {
  const sos = await SosEvent.findById(sosId);
  if (!sos || !S.crisis) return;
  await markAccounted(sos.workerId, 'SAFE', null, { system: true });
}

export async function markAccounted(workerId, status, by = null, { system = false } = {}) {
  const c = S.crisis;
  if (!c) throw new AppError(409, 'NO_ACTIVE_CRISIS', 'There is no active crisis');
  c.accounted = setAccounted(c.accounted ?? [], workerId, status, by?._id ?? null);
  note(`${system ? 'Worker marked' : `${by?.fullName ?? 'Staff'} marked a worker`} ${status}`);
  await Crisis.updateOne({ _id: c._id }, { $set: { accounted: c.accounted } }).catch(() => null);
  emitTo(staffRooms(c.zoneIds.map(String)), 'crisis:updated', { crisisId: String(c._id), accounted: { workerId: String(workerId), status } });
}

/** GpsUpdated from the bus. Only crisis zones' people are tracked, and only while a crisis is active. */
export async function onGps({ userId, lat, lng, accuracyM, ts }) {
  const c = S.crisis;
  if (!c) return;
  let pos = S.positions.get(userId);
  if (!pos) {
    const u = await User.findById(userId).select('fullName zoneId role');
    if (!u || !u.zoneId || !c.zoneIds.map(String).includes(String(u.zoneId))) return;
    pos = { userId, name: u.fullName, zoneId: String(u.zoneId) };
  }
  const next = { ...pos, lat, lng, accuracyM, ts };
  S.positions.set(userId, next);
  S.pings.push({ crisisId: c._id, userId, lat, lng, accuracyM, ts: new Date(ts) });
  const last = S.routedAt.get(userId);
  if (!last || haversineM(last, { lat, lng }) > MOVE_RECOMPUTE_M) {
    clearTimeout(S.recomputeTimer);
    S.recomputeTimer = setTimeout(() => recompute('worker moved').catch(() => null), RECOMPUTE_DEBOUNCE_MS);
    S.recomputeTimer.unref?.();
  }
  schedulePositions();
}

function schedulePositions() {
  if (S.posTimer) return;
  const wait = Math.max(0, S.lastPosEmit + POSITION_THROTTLE_MS - Date.now());
  S.posTimer = setTimeout(() => {
    S.posTimer = null;
    S.lastPosEmit = Date.now();
    if (!S.crisis) return;
    emitTo(staffRooms(S.crisis.zoneIds.map(String)), 'crisis:positions', { crisisId: String(S.crisis._id), positions: [...S.positions.values()] });
  }, wait);
  S.posTimer.unref?.();
}

/** Ask the rerouter (P2.9) for routes. A missing rerouter is not an error. */
export async function recompute(reason = 'manual') {
  const c = S.crisis;
  if (!c) return null;
  let mod;
  try {
    mod = await import('./rerouter/rerouter.service.js');
  } catch {
    return null;
  }
  const t0 = Date.now();
  const result = await mod.computeForCrisis({ crisis: c, positions: [...S.positions.values()] });
  S.routes = result.collection;
  c.routesComputedAt = new Date();
  for (const p of S.positions.values()) S.routedAt.set(p.userId, { lat: p.lat, lng: p.lng });
  logger.info(`crisis routes recomputed (${reason}) in ${Date.now() - t0} ms, ${result.collection.features.length} features`);
  emitTo(staffRooms(c.zoneIds.map(String)), 'crisis:routes', { crisisId: String(c._id), geojson: result.collection });
  for (const [workerId, features] of Object.entries(result.byWorker)) {
    emitTo([`user:${workerId}`], 'crisis:routes', { crisisId: String(c._id), geojson: { type: 'FeatureCollection', features } });
  }
  return result;
}

export async function roster(crisis = S.crisis) {
  if (!crisis) return [];
  const miners = await User.find({ role: 'miner', status: 'active', zoneId: { $in: crisis.zoneIds } }).sort({ fullName: 1 });
  return buildRoster(miners, crisis.accounted).map((r) => ({ ...r, position: S.positions.get(r.userId) ?? null }));
}

export async function resolve(admin, crisisId, body) {
  const c = S.crisis;
  if (!c || String(c._id) !== String(crisisId)) throw new AppError(404, 'NOT_FOUND', 'No such active crisis');
  const resolution = validateResolve(body);
  await Promise.all([flushPings(), flushTimeline()]);
  const resolvedAt = new Date();
  c.status = 'RESOLVED';
  c.resolvedAt = resolvedAt;
  await Crisis.updateOne({ _id: c._id }, { $set: { status: 'RESOLVED', resolvedAt, resolution: { ...resolution, resolvedBy: admin._id }, accounted: c.accounted }, $unset: { shareToken: '' } });
  await SosEvent.updateMany({ crisisId: c._id, status: 'ACTIVE' }, { $set: { status: 'RESOLVED' } });
  emitTo(['*'], 'crisis:resolved', { crisisId: String(c._id), falseAlarm: resolution.falseAlarm, resolvedAt: resolvedAt.toISOString() });
  bus.publish('CrisisResolved', { crisisId: String(c._id) });
  await audit(admin, 'CRISIS_RESOLVED', 'crisis', c._id, { falseAlarm: resolution.falseAlarm });
  const report = await buildReport(c, await roster(c), resolution).catch((err) => {
    logger.error({ err: err.message }, 'crisis report failed');
    return null;
  });
  clearTimeout(S.posTimer);
  clearTimeout(S.recomputeTimer);
  Object.assign(S, { crisis: null, positions: new Map(), routes: null, posTimer: null, recomputeTimer: null, routedAt: new Map(), timeline: [], pings: [] });
  return { crisisId: String(c._id), resolvedAt, reportId: report ? String(report._id) : null };
}

async function buildReport(c, rosterRows, resolution) {
  const pingCount = await GpsPing.countDocuments({ crisisId: c._id });
  const stored = await Crisis.findById(c._id);
  const zones = await Zone.find({ _id: { $in: c.zoneIds } });
  const summary = {
    crisisId: String(c._id), startedAt: c.startedAt, resolvedAt: c.resolvedAt, durationMin: Math.round((new Date(c.resolvedAt) - new Date(c.startedAt)) / 60000),
    triggers: c.triggers, zones: zones.map((z) => ({ code: z.code, name: z.name })), reason: c.reason, resolution, accounted: accountedCounts(rosterRows),
    roster: rosterRows.map(({ name, employeeId, status }) => ({ name, employeeId, status })), timeline: stored?.timeline ?? [], gpsPings: pingCount,
  };
  const report = await CrisisReport.findOneAndUpdate({ crisisId: c._id }, { $set: { summary } }, { upsert: true, new: true });
  const pdf = await buildCrisisReportPdf(summary);
  const path = `crisis/${c._id}/report.pdf`;
  await uploadBuffer(path, pdf, 'application/pdf');
  report.storagePath = path;
  await report.save();
  return report;
}

export async function getReport(crisisId) {
  const r = await CrisisReport.findOne({ crisisId });
  if (!r) throw new AppError(404, 'NOT_FOUND', 'Report not found');
  return { report: r.toJSON(), url: r.storagePath ? await signedUrl(r.storagePath, 15) : null };
}

export async function activeForClient(user) {
  const c = S.crisis;
  if (!c) return { active: false };
  const base = { active: true, crisis: publicView(c) };
  if (user.role === 'miner') return base;
  if (user.role === 'supervisor' && !c.zoneIds.map(String).includes(String(user.zoneId))) return base;
  const zoneCodes = (await Zone.find({ _id: { $in: c.zoneIds } })).map((z) => z.code);
  return { ...base, crisis: { ...publicView(c), zoneCodes, shareToken: c.shareToken, timeline: [...(c.timeline ?? []), ...S.timeline], blockedEdgeIds: c.blockedEdgeIds ?? [] }, roster: await roster(c), positions: [...S.positions.values()], routes: S.routes };
}

export async function setBlockedEdge(edgeId, blocked) {
  const c = S.crisis;
  if (!c) throw new AppError(409, 'NO_ACTIVE_CRISIS', 'There is no active crisis');
  const set = new Set(c.blockedEdgeIds ?? []);
  if (blocked) set.add(edgeId); else set.delete(edgeId);
  c.blockedEdgeIds = [...set];
  note(`${blocked ? 'Blocked' : 'Reopened'} tunnel ${edgeId}`);
  await Crisis.updateOne({ _id: c._id }, { $set: { blockedEdgeIds: c.blockedEdgeIds } }).catch(() => null);
  return recompute('edge change');
}

export function addTimeline(text) {
  if (S.crisis) note(text);
}

/** Boot: restore an ACTIVE crisis (after a restart) and start the write-behind timers. */
export async function initEngine() {
  const active = await Crisis.findOne({ status: 'ACTIVE' }).sort({ startedAt: -1 });
  if (active) {
    S.crisis = active.toObject();
    S.crisis.zoneIds = S.crisis.zoneIds.map(String);
    logger.warn(`Restored ACTIVE crisis ${active._id} after restart`);
    recompute('restart').catch(() => null);
  }
  S.timers.push(setInterval(() => flushPings().catch(() => null), PING_FLUSH_MS), setInterval(() => flushTimeline().catch(() => null), TIMELINE_FLUSH_MS));
  S.timers.forEach((t) => t.unref?.());
}

