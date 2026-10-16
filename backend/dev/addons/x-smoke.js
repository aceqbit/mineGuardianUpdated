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
