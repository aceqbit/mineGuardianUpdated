// Fakes what Phase 2 will later emit so every Phase 1 screen can be seen reacting. Writes NO Phase 2 collections.
// Usage:
//   node dev/simulate-phase2.js predict <checkInId> compliant|noncompliant|emergency
//   node dev/simulate-phase2.js reviewed <checkInId> confirm|override
//   node dev/simulate-phase2.js crisis-on <zoneCode> [workerPhone]
//   node dev/simulate-phase2.js crisis-off
//   node dev/simulate-phase2.js score <workerPhone> <score>
//   node dev/simulate-phase2.js breach <zoneCode>
import crypto from 'node:crypto';
import { emit, connectMongo } from './lib/common.js';

const [, , cmd, ...args] = process.argv;
const nowIso = () => new Date().toISOString();
const e164 = (phone) => `+91${String(phone).replace(/\D/g, '').slice(-10)}`;

// ---- tiny graph search over the layout (junction graph) ----
export function buildGraph(layout) {
  const feats = layout.geojson.features;
  const edges = feats.filter((f) => f.properties.kind === 'tunnel' && f.properties.status !== 'blocked');
  const exits = feats.filter((f) => f.properties.kind === 'exit').map((f) => ({ ...f.properties, coord: f.geometry.coordinates }));
  const adj = new Map();
  const add = (a, b, edge, len, forward) => {
    if (!adj.has(a)) adj.set(a, []);
    adj.get(a).push({ to: b, edge, len, forward });
  };
  const hav = (a, b) => {
    const R = 6371008.8, rad = (d) => (d * Math.PI) / 180;
    const dLat = rad(b[1] - a[1]), dLng = rad(b[0] - a[0]);
    const s = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[1])) * Math.cos(rad(b[1])) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(s));
  };
  for (const f of edges) {
    const p = f.properties;
    const c = f.geometry.coordinates;
    let len = 0;
    for (let i = 1; i < c.length; i++) len += hav(c[i - 1], c[i]);
    add(p.fromNode, p.toNode, f, len, true);
    add(p.toNode, p.fromNode, f, len, false);
  }
  const junctions = new Map(feats.filter((f) => f.properties.kind === 'junction').map((f) => [f.properties.id, f.geometry.coordinates]));
  return { adj, exits, junctions, hav };
}

export function routesFrom(graph, startNode, max = 3) {
  const { adj, exits } = graph;
  const dist = new Map([[startNode, 0]]);
  const prev = new Map();
  const open = new Set([startNode]);
  while (open.size) {
    let u = null;
    for (const n of open) if (u === null || dist.get(n) < dist.get(u)) u = n;
    open.delete(u);
    for (const { to, len, edge, forward } of adj.get(u) || []) {
      const nd = dist.get(u) + len;
      if (nd < (dist.get(to) ?? Infinity)) {
        dist.set(to, nd);
        prev.set(to, { from: u, edge, forward });
        open.add(to);
      }
    }
  }
  const out = [];
  for (const ex of exits) {
    const d = dist.get(ex.node);
    if (d === undefined) continue;
    const coords = [];
    let cur = ex.node;
    const stack = [];
    while (cur !== startNode) {
      const p = prev.get(cur);
      stack.push(p);
      cur = p.from;
    }
    for (const p of stack.reverse()) {
      const c = p.forward ? p.edge.geometry.coordinates : [...p.edge.geometry.coordinates].reverse();
      for (const pt of c) if (!coords.length || coords[coords.length - 1][0] !== pt[0] || coords[coords.length - 1][1] !== pt[1]) coords.push(pt);
    }
    if (coords.length < 2) coords.push(coords[0]);
    out.push({ exit: ex, distanceM: d, coords });
  }
  return out.sort((a, b) => a.distanceM - b.distanceM).slice(0, max);
}

async function main() {
  if (!cmd) {
    console.error('Commands: predict | reviewed | crisis-on | crisis-off | score | breach (see header)');
    process.exit(1);
  }

  if (cmd === 'crisis-off') {
    await emit('crisis:resolved', ['*'], { crisisId: 'sim-crisis', resolvedAt: nowIso(), falseAlarm: false });
    console.log('crisis:resolved sent');
    return;
  }

  const mongoose = await connectMongo();
  const db = mongoose.connection;
  const col = (n) => db.collection(n);
  try {
    if (cmd === 'predict') {
      const [id, kind = 'noncompliant'] = args;
      const ci = await col('check_ins').findOne({ _id: new mongoose.Types.ObjectId(id) });
      if (!ci) throw new Error('check-in not found');
      const base = { checkInId: String(ci._id), reviewId: new mongoose.Types.ObjectId().toString(), workerId: String(ci.workerId), zoneId: String(ci.zoneId) };
      const data = {
        compliant: { verdict: 'COMPLIANT', overallConfidence: 0.93, criticality: { level: 'NONE', score: 0 }, summary: 'Compliant · NONE 0/100 — all required PPE visible.', emergency: { detected: false, possible: false, type: 'NONE' } },
        noncompliant: { verdict: 'NON_COMPLIANT', overallConfidence: 0.91, criticality: { level: 'HIGH', score: 58 }, summary: 'Non-compliant · HIGH 58/100 — Helmet absent, gloves uncertain.', emergency: { detected: false, possible: false, type: 'NONE' } },
        emergency: { verdict: 'NEEDS_MANUAL_REVIEW', overallConfidence: 0.82, criticality: { level: 'CRITICAL', score: 100 }, summary: 'Possible fire and smoke in frame — review now.', emergency: { detected: false, possible: true, type: 'FIRE' } },
      }[kind];
      if (!data) throw new Error('kind must be compliant | noncompliant | emergency');
      const payload = { ...base, ...data };
      await emit('compliance:predicted', [`zone:${ci.zoneId}:supervisors`, 'role:admin', `user:${ci.workerId}`], payload);
      console.log(`compliance:predicted (${kind}) sent for ${id}`);
    } else if (cmd === 'reviewed') {
      const [id, action = 'confirm'] = args;
      const ci = await col('check_ins').findOne({ _id: new mongoose.Types.ObjectId(id) });
      if (!ci) throw new Error('check-in not found');
      const override = action === 'override';
      await emit('compliance:reviewed', [`user:${ci.workerId}`, `zone:${ci.zoneId}:supervisors`, 'role:admin'], {
        checkInId: String(ci._id), reviewId: new mongoose.Types.ObjectId().toString(), workerId: String(ci.workerId),
        finalVerdict: override ? 'COMPLIANT' : 'NON_COMPLIANT', missing: override ? [] : ['HELMET'], decidedBy: 'sim', action: override ? 'OVERRIDE' : 'CONFIRM',
      });
      console.log(`compliance:reviewed (${action}) sent for ${id}`);
    } else if (cmd === 'crisis-on') {
      const [zoneCode, phone] = args;
      const zone = await col('zones').findOne({ code: zoneCode });
      if (!zone) throw new Error(`zone ${zoneCode} not found`);
      const crisisId = new mongoose.Types.ObjectId().toString();
      await emit('crisis:activated', ['*'], { crisisId, trigger: { type: 'SOS', refId: 'sim-sos' }, zoneIds: [String(zone._id)], startedAt: nowIso(), headline: `SOS — simulated · ${zoneCode}` });
      console.log('crisis:activated sent');
      const worker = phone
        ? await col('users').findOne({ email: String(phone).toLowerCase() })
        : await col('users').findOne({ role: 'miner', zoneId: zone._id });
      if (!worker) throw new Error('worker not found');
      const layout = await col('layouts').find().sort({ version: -1 }).limit(1).next();
      const graph = buildGraph(layout);
      // nearest junction to the zone centre as the worker's position
      const ring = zone.polygon.coordinates[0];
      const centre = [ring.reduce((s, p) => s + p[0], 0) / ring.length, ring.reduce((s, p) => s + p[1], 0) / ring.length];
      let start = null, best = Infinity;
      for (const [id, c] of graph.junctions) {
        const d = graph.hav(centre, c);
        if (d < best) (best = d, start = id);
      }
      const routes = routesFrom(graph, start, 3);
      const features = routes.map((r, i) => ({
        type: 'Feature',
        geometry: { type: 'LineString', coordinates: r.coords },
        properties: {
          crisisId, workerId: String(worker._id), workerName: worker.fullName, rank: i + 1, recommended: i === 0, exitId: r.exit.id, exitName: r.exit.name,
          exitType: r.exit.exitType, distanceM: Math.round(r.distanceM), etaSec: Math.round(r.distanceM / 1.1), risk: 0, congestion: 0,
          reasons: i === 0 ? ['Fastest'] : ['Alternative exit'], positionUnknown: false, computedAt: nowIso(),
        },
      }));
      await emit('crisis:routes', ['role:admin', `zone:${zone._id}:supervisors`, `user:${worker._id}`], { crisisId, computedAt: nowIso(), geojson: { type: 'FeatureCollection', features } });
      console.log(`crisis:routes sent: ${features.length} routes for ${worker.fullName} from ${start}`);
    } else if (cmd === 'score') {
      const [phone, score] = args;
      const w = await col('users').findOne({ email: String(phone).toLowerCase() });
      if (!w) throw new Error('worker not found');
      const s = Number(score);
      await emit('score:updated', [`user:${w._id}`], { workerId: String(w._id), score: s, rank: 3, xp: 1200, streak: 6, riskBand: s >= 700 ? 'GREEN' : s >= 400 ? 'AMBER' : 'RED' });
      await emit('leaderboard:updated', ['public:leaderboard'], { updatedAt: nowIso(), top: [{ workerId: String(w._id), name: w.fullName, zoneCode: 'Z-B', score: s, streak: 6, rank: 1, badges: [] }] });
      console.log(`score:updated + leaderboard:updated sent for ${w.fullName}`);
    } else if (cmd === 'breach') {
      const [zoneCode] = args;
      const zone = await col('zones').findOne({ code: zoneCode });
      if (!zone) throw new Error('zone not found');
      const sup = await col('users').findOne({ role: 'supervisor', zoneId: zone._id });
      await emit('sla:breach', ['role:admin'], { reviewId: crypto.randomBytes(12).toString('hex'), checkInId: crypto.randomBytes(12).toString('hex'), supervisorId: String(sup?._id ?? ''), supervisorName: sup?.fullName ?? 'Supervisor', zoneId: String(zone._id), minutesPending: 35, remindersSent: 3 });
      console.log('sla:breach sent');
    } else {
      throw new Error(`unknown command ${cmd}`);
    }
  } finally {
    await mongoose.disconnect();
  }
}

if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('simulate-phase2.js')) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
