// Add-on pack gate (CLAUDE.md section 23.8). Self-contained: builds a fixture in the throwaway `mineguardian_xtest` database,
// starts its own API on PORT (default 4100) with the dev bypass, runs every add-on check, stops the API and drops the DB.
// Usage: node dev/addons/x-smoke.js [--keep]      (--keep leaves the test DB for inspection)
// Needs only MONGODB_URI in backend/.env. Never touches the real database. Exits non-zero on any FAIL.
import { fixture, drop, server } from './xtest.js';
import { connectSio } from '../lib/sio-wire.js';

const PORT = Number(process.env.XTEST_PORT || 4100);
const BASE = `http://127.0.0.1:${PORT}`;
const rows = [];
const step = async (name, fn) => {
  try {
    rows.push({ name, ok: true, detail: (await fn()) ?? '' });
  } catch (e) {
    rows.push({ name, ok: false, detail: e.message });
  }
};
const expect = (cond, msg) => {
  if (!cond) throw new Error(msg);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(path, as, { method = 'GET', json } = {}) {
  const headers = { 'x-dev-user-id': as };
  if (json !== undefined) headers['content-type'] = 'application/json';
  const res = await fetch(`${BASE}${path}`, { method, headers, body: json === undefined ? undefined : JSON.stringify(json) });
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { status: res.status, data };
}

const ids = await fixture();
const child = server(PORT);
let log = '';
child.stdout.on('data', (b) => (log += b));
child.stderr.on('data', (b) => (log += b));
const sockets = [];
const sock = async (userId) => {
  const s = connectSio(BASE, { devUserId: userId });
  await s.ready;
  sockets.push(s);
  return s;
};

try {
  let up = false;
  for (let i = 0; i < 40 && !up; i += 1) {
    await sleep(500);
    up = await fetch(`${BASE}/api/health`).then((r) => r.ok).catch(() => false);
  }
  if (!up) throw new Error(`API did not start on ${PORT}:\n${log.slice(-2000)}`);

  const [m1, m2, m3] = ids.minersA;

  // ---------------- X1/X2 profiles ----------------
  await step('profiles: admin lists everyone (7 users)', async () => {
    const r = await api('/api/profiles', ids.admin);
    expect(r.status === 200, `status ${r.status}`);
    expect(r.data.total === 7, `total ${r.data.total}`);
    return `total=${r.data.total}`;
  });
  await step('profiles: Z-A supervisor lists own miners + self only', async () => {
    const r = await api('/api/profiles', ids.supA);
    const got = r.data.items.map((i) => i.id).sort();
    expect(JSON.stringify(got) === JSON.stringify([...ids.minersA, ids.supA].sort()), `got ${got}`);
    expect(r.data.items.find((i) => i.id === m3).riskBand === 'RED', 'supervisor should see the risk band');
  });
  await step('profiles: Z-A supervisor cannot list or open Z-B', async () => {
    const a = await api(`/api/profiles?zoneId=${ids.zoneB}`, ids.supA);
    const b = await api(`/api/profiles/${ids.minerB}`, ids.supA);
    expect(a.status === 403 && b.status === 403, `${a.status} ${b.status}`);
    expect(b.data.error.code === 'FORBIDDEN_SCOPE', b.data.error.code);
  });
  await step('profiles: miner sees crew cards without risk band or score', async () => {
    const r = await api('/api/profiles', m2);
    expect(r.status === 200, `status ${r.status}`);
    expect(r.data.items.length === 4, `${r.data.items.length} cards`);
    for (const c of r.data.items) expect(c.riskBand === undefined, `risk band leaked on ${c.id}`);
    expect(!r.data.items.some((c) => c.id === ids.minerB), 'Z-B miner leaked');
  });
  await step('profiles: crew detail has no phone, email, calendar or risk band', async () => {
    const r = await api(`/api/profiles/${m1}`, m2);
    const p = r.data.profile;
    expect(p.level === 'crew', p.level);
    for (const k of ['email', 'phoneMasked', 'medicalNotes', 'calendar', 'hazards']) expect(p[k] === undefined, `${k} leaked`);
    expect(p.score?.riskBand === undefined && p.score?.score === undefined, 'score leaked');
    expect(p.score?.rank === 1, `rank ${p.score?.rank}`);
  });
  await step('profiles: own profile has today, 30-day calendar, no risk band', async () => {
    const r = await api(`/api/profiles/${m1}`, m1);
    const p = r.data.profile;
    expect(p.level === 'self', p.level);
    expect(p.calendar.length === 30, `calendar ${p.calendar?.length}`);
    expect(p.today.verdict === 'NON_COMPLIANT', `today ${JSON.stringify(p.today)}`);
    expect(p.hazards.counts.OPEN === 1, `hazards ${JSON.stringify(p.hazards)}`);
    expect(p.score.riskBand === undefined && p.score.score === 800, JSON.stringify(p.score));
    expect(p.phoneMasked && !p.phoneMasked.includes('500111'), 'phone not masked');
  });
  await step('profiles: supervisor detail shows team stats', async () => {
    const r = await api(`/api/profiles/${ids.supA}`, ids.supA);
    expect(r.data.profile.supervisorStats?.teamSize === 3, JSON.stringify(r.data.profile.supervisorStats));
  });
  await step('profiles: miner can edit own designation, nothing else', async () => {
    const ok = await api(`/api/profiles/${m1}`, m1, { method: 'PATCH', json: { designation: 'Shot firer' } });
    const bad = await api(`/api/profiles/${m1}`, m1, { method: 'PATCH', json: { bloodGroup: 'A+' } });
    const other = await api(`/api/profiles/${m2}`, m1, { method: 'PATCH', json: { designation: 'x' } });
    expect(ok.status === 200 && ok.data.profile.designation === 'Shot firer', `ok ${ok.status}`);
    expect(bad.status === 403 && bad.data.error.code === 'FORBIDDEN_FIELD', `bad ${bad.status}`);
    expect(other.status === 403, `other ${other.status}`);
  });
  await step('profiles: admin edit pushes profile:updated live to supervisor and crew', async () => {
    const sup = await sock(ids.supA);
    const crew = await sock(m1);
    const outsider = await sock(ids.supB);
    const r = await api(`/api/profiles/${m2}`, ids.admin, { method: 'PATCH', json: { designation: 'Roof bolter', certifications: [{ name: 'Gas testing', expiresAt: new Date(Date.now() + 10 * 864e5).toISOString() }] } });
    expect(r.status === 200, `patch ${r.status} ${JSON.stringify(r.data)}`);
    expect(r.data.profile.certificationsExpiring.length === 1, 'expiring certification not flagged');
    const a = await sup.waitFor('profile:updated', (e) => e.data.userId === m2);
    await crew.waitFor('profile:updated', (e) => e.data.userId === m2);
    await sleep(600);
    expect(!outsider.events.some((e) => e.name === 'profile:updated' && e.data.data.userId === m2), 'Z-B supervisor received a Z-A change');
    expect(a.v === 1 && a.id && a.data.changed.includes('identity'), JSON.stringify(a));
    return `changed=${a.data.changed.join(',')}`;
  });
  await step('profiles: a hazard status change pushes profile:updated to the reporter', async () => {
    const me = await sock(m1);
    const list = await api(`/api/hazards?zoneId=${ids.zoneA}`, ids.supA);
    const hz = (list.data.items ?? list.data.hazards ?? list.data)[0];
    const r = await api(`/api/hazards/${hz.id ?? hz._id}`, ids.supA, { method: 'PATCH', json: { status: 'ACKNOWLEDGED' } });
    expect(r.status === 200, `ack ${r.status} ${JSON.stringify(r.data)}`);
    const e = await me.waitFor('profile:updated', (x) => x.data.changed.includes('hazards'));
    return `changed=${e.data.changed.join(',')}`;
  });

  // ---------------- X3 live tracking ----------------
  await step('tracking: gps:update rejects a bad heading/source, accepts fused fields', async () => {
    const s = await sock(m1);
    const bad = await s.emit('gps:update', { lat: 23.745, lng: 86.412, accuracyM: 4, ts: new Date().toISOString(), headingDeg: 400 });
    const bad2 = await s.emit('gps:update', { lat: 23.745, lng: 86.412, accuracyM: 4, ts: new Date().toISOString(), source: 'MAGIC' });
    const ok = await s.emit('gps:update', { lat: 23.745, lng: 86.412, accuracyM: 4, ts: new Date().toISOString(), headingDeg: 90, speedMps: 1.1, source: 'FUSED', tunnelId: 'T-J1-J2' });
    expect(bad.error === 'INVALID_HEADING' && bad2.error === 'INVALID_SOURCE' && ok.ok === true, JSON.stringify([bad, bad2, ok]));
  });
  await step('tracking: a walking miner moves on the admin and own-zone supervisor feeds, not on Z-B', async () => {
    const adm = await sock(ids.admin);
    const sup = await sock(ids.supA);
    const supB = await sock(ids.supB);
    const walker = await sock(m2);
    adm.clear();
    sup.clear();
    supB.clear();
    for (let i = 0; i < 5; i += 1) {
      const ack = await walker.emit('gps:update', { lat: 23.745 + i * 0.00002, lng: 86.412, accuracyM: 6, ts: new Date().toISOString(), headingDeg: 0, speedMps: 1.2, source: 'GPS' });
      expect(ack.ok, JSON.stringify(ack));
      await sleep(1100);
    }
    const seen = adm.events.filter((x) => x.name === 'tracking:positions').flatMap((x) => x.data.data.positions).filter((p) => p.userId === m2);
    const lats = [...new Set(seen.map((p) => p.lat))];
    expect(lats.length >= 4, `admin saw ${lats.length} distinct positions`);
    expect(lats[lats.length - 1] > lats[0], 'not moving north');
    expect(seen.at(-1).presence === 'LIVE' && seen.at(-1).name === 'XT XMIN-A2', JSON.stringify(seen.at(-1)));
    expect(sup.events.some((x) => x.name === 'tracking:positions' && x.data.data.positions.some((p) => p.userId === m2)), 'Z-A supervisor saw nothing');
    expect(!supB.events.some((x) => x.name === 'tracking:positions' && x.data.data.positions.some((p) => p.zoneId === ids.zoneA)), 'Z-B supervisor received Z-A positions');
    const perSec = adm.events.filter((x) => x.name === 'tracking:positions').length;
    expect(perSec <= 7, `${perSec} admin emits in ~5.5 s (throttle is 1/s)`);
    return `${lats.length} positions, ${perSec} emits`;
  });
  await step('tracking: live snapshot scoped (supervisor own zone, miner refused)', async () => {
    const a = await api('/api/tracking/live', ids.admin);
    const s = await api('/api/tracking/live', ids.supA);
    const x = await api(`/api/tracking/live?zoneId=${ids.zoneB}`, ids.supA);
    const m = await api('/api/tracking/live', m1);
    expect(a.status === 200 && a.data.positions.some((p) => p.userId === m2), `admin ${a.status}`);
    expect(s.status === 200 && s.data.positions.every((p) => p.zoneId === ids.zoneA), `sup ${s.status}`);
    expect(x.status === 403 && m.status === 403, `${x.status} ${m.status}`);
  });
  await step('tracking: profile shows the live presence', async () => {
    const r = await api(`/api/profiles/${m2}`, ids.supA);
    expect(r.data.profile.presence?.presence === 'LIVE', JSON.stringify(r.data.profile.presence));
  });
  await step('tracking: surface route without ORS_API_KEY is 503 (MANUAL: set the key)', async () => {
    const r = await api('/api/tracking/surface-route?fromLat=23.74&fromLng=86.41&toLat=23.75&toLng=86.42', m1);
    expect([200, 503].includes(r.status), `status ${r.status}`);
    return r.status === 503 ? 'not configured' : `${r.data.distanceM} m`;
  });
} finally {
  for (const s of sockets) s.close();
  child.kill();
  if (!process.argv.includes('--keep')) await drop().catch(() => {});
}

const w = Math.max(...rows.map((r) => r.name.length), 10);
for (const r of rows) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(w)}  ${r.detail ?? ''}`);
const failed = rows.filter((r) => !r.ok).length;
console.log(`\n${rows.length - failed}/${rows.length} passed`);
process.exit(failed ? 1 : 0);
