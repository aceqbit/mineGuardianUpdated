// What the voice agent knows about a call (CLAUDE.md section 23.5): only real data, read from raw collections so the
// voice module depends on no other module's internals. Missing data is simply left out of the packet.
import mongoose from 'mongoose';
import { haversineM } from '../../core/geo.js';

const raw = (n) => mongoose.connection.collection(n);
const safe = async (fn, fb = null) => {
  try {
    return await fn();
  } catch {
    return fb;
  }
};

async function nearestJunction(lat, lng) {
  const layout = await raw('layouts').find().sort({ version: -1 }).limit(1).next();
  let best = null;
  let bestD = Infinity;
  for (const f of layout?.geojson?.features ?? []) {
    if (f.properties?.kind !== 'junction') continue;
    const [jl, jt] = f.geometry.coordinates;
    const d = haversineM({ lat, lng }, { lat: jt, lng: jl });
    if (d < bestD) {
      bestD = d;
      best = f.properties.id;
    }
  }
  return bestD <= 250 ? best : null;
}

export async function buildPacket(caller, { reason, now = Date.now() } = {}) {
  const id = caller._id;
  const zone = caller.zoneId ? await safe(() => raw('zones').findOne({ _id: caller.zoneId }, { projection: { code: 1 } })) : null;
  const [pos, sos, crisis, hazards] = await Promise.all([
    safe(() => raw('live_positions').findOne({ userId: String(id) })),
    safe(() => raw('sos_events').findOne({ workerId: id, status: 'ACTIVE' }, { sort: { createdAt: -1 } })),
    safe(() => raw('crises').findOne({ status: 'ACTIVE' }, { sort: { startedAt: -1 } })),
    caller.zoneId ? safe(() => raw('hazards').find({ zoneId: caller.zoneId, status: { $in: ['OPEN', 'ACKNOWLEDGED'] } }, { projection: { category: 1 } }).limit(20).toArray(), []) : [],
  ]);
  let crisisZoneCodes = [];
  if (crisis?.zoneIds?.length) crisisZoneCodes = (await safe(() => raw('zones').find({ _id: { $in: crisis.zoneIds } }, { projection: { code: 1 } }).toArray(), [])).map((z) => z.code);
  const packet = {
    caller: { name: caller.fullName, role: caller.role, zoneCode: zone?.code ?? null, employeeId: caller.employeeId },
    reason: reason ? String(reason).slice(0, 200) : null,
  };
  if (pos?.lat != null) {
    packet.position = {
      lat: pos.lat, lng: pos.lng, accuracyM: pos.accuracyM, tunnelId: pos.tunnelId ?? null,
      junction: await safe(() => nearestJunction(pos.lat, pos.lng)), ageSec: Math.max(0, (now - new Date(pos.ts).getTime()) / 1000),
    };
  }
  if (sos) packet.sos = { ageSec: Math.max(0, (now - new Date(sos.createdAt).getTime()) / 1000) };
  if (crisis) packet.crisis = { reason: crisis.reason ?? null, zoneCodes: crisisZoneCodes };
  if (hazards?.length) packet.hazards = { count: hazards.length, categories: [...new Set(hazards.map((h) => String(h.category).replace(/_/g, ' ').toLowerCase()))] };
  return packet;
}
