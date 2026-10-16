import { Server } from 'socket.io';
import { v4 as uuid } from 'uuid';
import { SOCKET_EVENTS } from '../contracts/events.js';
import { POSITION_SOURCE } from '../contracts/enums.js';
import { verifySocketHandshake } from './auth.js';
import { publish } from './bus.js';
import { logger } from './logger.js';
import { env } from '../config/env.js';

let io = null;
/** userId -> { sockets:Set<string>, role, zoneId, name, lastGps } */
export const presence = new Map();
const clientHandlers = new Map();

export const envelope = (data) => ({ v: 1, id: uuid(), ts: new Date().toISOString(), data });

export function getIo() {
  return io;
}

/** emitTo(['user:1','role:admin'] | ['*'], event, data) */
export function emitTo(rooms, event, data) {
  if (!SOCKET_EVENTS.serverToClient.includes(event)) {
    throw new Error(`Unknown server->client socket event: ${event}`);
  }
  if (!io) return;
  const env_ = envelope(data);
  const list = Array.isArray(rooms) ? rooms : [rooms];
  if (list.includes('*')) {
    io.emit(event, env_);
    return;
  }
  let target = io;
  for (const r of list) target = target.to(r);
  target.emit(event, env_);
}

export function registerClientHandler(event, handler) {
  clientHandlers.set(event, handler);
}

export const isOnline = (userId) => (presence.get(String(userId))?.sockets.size ?? 0) > 0;

const num = (v) => typeof v === 'number' && Number.isFinite(v);

function handleGps(ctx, data) {
  const { lat, lng, accuracyM, ts, sosId } = data || {};
  if (!num(lat) || lat < -90 || lat > 90) return { ok: false, error: 'INVALID_LAT' };
  if (!num(lng) || lng < -180 || lng > 180) return { ok: false, error: 'INVALID_LNG' };
  if (!num(accuracyM) || accuracyM < 0) return { ok: false, error: 'INVALID_ACCURACY' };
  if (typeof ts !== 'string' || Number.isNaN(Date.parse(ts))) return { ok: false, error: 'INVALID_TS' };
  // Add-on X0: optional fused-tracking fields; older clients omit them.
  const { headingDeg, speedMps, source, tunnelId } = data;
  if (headingDeg != null && (!num(headingDeg) || headingDeg < 0 || headingDeg >= 360)) return { ok: false, error: 'INVALID_HEADING' };
  if (speedMps != null && (!num(speedMps) || speedMps < 0 || speedMps > 20)) return { ok: false, error: 'INVALID_SPEED' };
  if (source != null && !POSITION_SOURCE.includes(source)) return { ok: false, error: 'INVALID_SOURCE' };
  if (tunnelId != null && (typeof tunnelId !== 'string' || tunnelId.length > 64)) return { ok: false, error: 'INVALID_TUNNEL' };
  const extra = { headingDeg: headingDeg ?? null, speedMps: speedMps ?? null, source: source ?? 'GPS', tunnelId: tunnelId ?? null };
  const p = presence.get(String(ctx.user._id));
  if (p) p.lastGps = { lat, lng, accuracyM, ts, sosId: sosId ?? null, ...extra };
  publish('GpsUpdated', { userId: String(ctx.user._id), lat, lng, accuracyM, ts, sosId: sosId ?? null, ...extra });
  return { ok: true };
}

export function initSocket(httpServer) {
  io = new Server(httpServer, {
    path: '/socket.io',
    pingInterval: 10000,
    pingTimeout: 8000,
    cors: { origin: env.CORS_ORIGINS === '*' ? true : env.CORS_ORIGINS.split(',') },
  });

  io.use(async (socket, next) => {
    try {
      socket.data.user = await verifySocketHandshake(socket.handshake);
      next();
    } catch (e) {
      next(new Error(e.message || 'UNAUTHENTICATED'));
    }
  });

  io.on('connection', (socket) => {
    const u = socket.data.user;
    const uid = String(u._id);
    socket.join([`user:${uid}`, `role:${u.role}`, 'public:leaderboard']);
    if (u.zoneId) {
      socket.join(`zone:${u.zoneId}`);
      if (u.role === 'supervisor') socket.join(`zone:${u.zoneId}:supervisors`);
    }
    const p = presence.get(uid) || { sockets: new Set(), role: u.role, zoneId: u.zoneId ? String(u.zoneId) : null, name: u.fullName, lastGps: null };
    p.sockets.add(socket.id);
    presence.set(uid, p);

    const ctx = { socket, user: u };
    const wire = (event, fn) =>
      socket.on(event, async (data, ack) => {
        try {
          const payload = data && typeof data === 'object' && 'data' in data && data.v ? data.data : data;
          const res = await fn(ctx, payload);
          if (typeof ack === 'function') ack(res ?? { ok: true });
        } catch (err) {
          logger.warn({ err: err.message, event }, 'socket handler error');
          if (typeof ack === 'function') ack({ ok: false, error: 'INTERNAL' });
        }
      });

    wire('gps:update', handleGps);
    for (const [event, handler] of clientHandlers) wire(event, handler);

    socket.on('disconnect', () => {
      const cur = presence.get(uid);
      if (!cur) return;
      cur.sockets.delete(socket.id);
      if (cur.sockets.size === 0) presence.set(uid, { ...cur, sockets: new Set() });
    });
  });

  return io;
}
