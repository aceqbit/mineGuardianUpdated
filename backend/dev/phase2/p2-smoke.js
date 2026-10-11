// Phase 2 gate. Needs: the server running (npm run dev), `npm run seed` loaded, FIREBASE_WEB_API_KEY in the shell, TWILIO_DRY_RUN=true.
// Walks check-in -> AI -> decision, scores, rewards, admin tools, contacts safety, broadcast rules, then a full crisis (SOS -> routes -> accounted -> resolve).
// Prints PASS/FAIL per step and exits non-zero on any failure. The crisis steps run last and leave no active crisis behind.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { BASE, api, printTable } from '../lib/common.js';
import { getToken } from '../get-token.js';
import { demoEmailFor } from '../../seed/accounts.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const sampleDir = path.join(here, '..', '..', 'seed', 'sample');
const anchor = { lat: Number(process.env.DEMO_ANCHOR_LAT ?? 23.746), lng: Number(process.env.DEMO_ANCHOR_LNG ?? 86.415) };

const rows = [];
const step = async (name, fn) => {
  try {
    rows.push({ name, ok: true, detail: (await fn()) ?? '' });
    return true;
  } catch (e) {
    rows.push({ name, ok: false, detail: e.message });
    return false;
  }
};
const expect = (cond, msg) => {
  if (!cond) throw new Error(msg);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, { tries = 40, every = 1500, what = 'condition' } = {}) {
  for (let i = 0; i < tries; i += 1) {
    const v = await fn();
    if (v) return v;
    await sleep(every);
  }
  throw new Error(`timed out waiting for ${what}`);
}

async function photo() {
  const p = path.join(sampleDir, 'worker_full_body.jpg');
  let buf;
  if (fs.existsSync(p)) buf = fs.readFileSync(p);
  else {
    const size = 900;
    const raw = Buffer.alloc(size * size * 3);
    for (let y = 0; y < size; y += 1) for (let x = 0; x < size; x += 1) {
      const v = (Math.floor(x / 12) + Math.floor(y / 12)) % 2 === 0 ? 200 : 60;
      const i = (y * size + x) * 3;
      raw[i] = v; raw[i + 1] = v - 10; raw[i + 2] = v - 20;
    }
    buf = await sharp(raw, { raw: { width: size, height: size, channels: 3 } }).jpeg({ quality: 92 }).toBuffer();
  }
  const { data, info } = await sharp(buf).raw().toBuffer({ resolveWithObject: true });
  data[0] = (data[0] + crypto.randomInt(1, 200)) % 255; // new hash every run
  return sharp(data, { raw: info }).jpeg({ quality: 92 }).toBuffer();
}

const tokens = {};
let reviewData;
let me = {};

await step('health + AI health (admin)', async () => {
  expect((await api('/api/health')).status === 200, 'health');
  tokens.admin = await getToken(demoEmailFor('ADM-0001'), 'Admin1');
  const r = await api('/api/ai/health', { token: tokens.admin });
  expect(r.status === 200, `ai health ${r.status}`);
  return `mode=${r.data.mlMode} yolo=${r.data.yoloProvider}`;
});
await step('sign in miner + supervisor', async () => {
  tokens.miner = await getToken(demoEmailFor('MIN-0105'), 'Miner1');
  tokens.supervisor = await getToken(demoEmailFor('SUP-0012'), 'Super1');
  me.supervisor = (await api('/api/auth/me', { token: tokens.supervisor })).data;
  me.miner = (await api('/api/auth/me', { token: tokens.miner })).data;
  expect(me.supervisor?.zone?.id && me.miner?.user?.id, 'profiles');
});

let checkInId;
await step('check-in is analysed and a review appears', async () => {
  const buf = await photo();
  const form = new FormData();
  form.append('image', new Blob([buf], { type: 'image/jpeg' }), 'p.jpg');
  const fields = { clientId: crypto.randomUUID(), capturedAt: new Date().toISOString(), uploadStartedAt: new Date().toISOString(), source: 'camera', attempt: 1, lat: anchor.lat, lng: anchor.lng, accuracyM: 8, sha256: crypto.createHash('sha256').update(buf).digest('hex'), clientQuality: JSON.stringify({ blurScore: 120, poseChecked: false }) };
  for (const [k, v] of Object.entries(fields)) form.append(k, String(v));
  const r = await api('/api/checkins', { token: tokens.miner, method: 'POST', form });
  expect(r.status === 201, `post ${r.status} ${JSON.stringify(r.data?.error ?? '')}`);
  checkInId = r.data.checkIn.id ?? r.data.checkIn._id;
  reviewData = await until(async () => {
    const x = await api(`/api/compliance/reviews/by-checkin/${checkInId}`, { token: tokens.supervisor });
    return x.status === 200 ? x.data : null;
  }, { what: 'the AI review' });
  return `verdict=${reviewData.review.ai?.overallVerdict}`;
});

await step('decision rules: incomplete items 400, decide 200, decide again 409', async () => {
  const id = reviewData.review.id ?? reviewData.review._id;
  const required = reviewData.zone.requiredPpe;
  const bad = await api(`/api/compliance/reviews/${id}/decision`, { token: tokens.supervisor, method: 'POST', json: { action: 'CONFIRM', items: [{ key: required[0], status: 'PRESENT' }] } });
  expect(bad.status === 400 && bad.data?.error?.code === 'ITEMS_INCOMPLETE', `incomplete gave ${bad.status} ${bad.data?.error?.code}`);
  const aiBy = new Map((reviewData.review.ai?.items ?? []).map((i) => [i.key, i.status]));
  const clean = required.every((k) => ['PRESENT', 'ABSENT'].includes(aiBy.get(k)));
  const items = required.map((k) => ({ key: k, status: aiBy.get(k) === 'ABSENT' ? 'ABSENT' : 'PRESENT' }));
  const body = clean ? { action: 'CONFIRM', items } : { action: 'OVERRIDE', items, note: 'Smoke test: decided by the supervisor after reviewing the photo' };
  const ok = await api(`/api/compliance/reviews/${id}/decision`, { token: tokens.supervisor, method: 'POST', json: body });
  expect(ok.status === 200, `decide ${ok.status} ${JSON.stringify(ok.data?.error ?? '')}`);
  const again = await api(`/api/compliance/reviews/${id}/decision`, { token: tokens.supervisor, method: 'POST', json: body });
  expect(again.status === 409 && again.data?.error?.code === 'ALREADY_DECIDED', `second decision gave ${again.status}`);
  const url = await api(`/api/compliance/reviews/${id}/report-url`, { token: tokens.supervisor });
  expect(url.status === 200 && url.data.url, `report-url ${url.status}`);
});

await step('scoring: leaderboard, my standing, zone risk bands (supervisor only)', async () => {
  await sleep(1500);
  const lb = await api('/api/leaderboard', { token: tokens.miner });
  expect(lb.status === 200 && Array.isArray(lb.data), `leaderboard ${lb.status}`);
  const mine = await api('/api/leaderboard/me', { token: tokens.miner });
  expect(mine.status === 200 && typeof mine.data.score === 'number', `me ${mine.status}`);
  const zone = await api(`/api/scores/zone/${me.supervisor.zone.id}`, { token: tokens.supervisor });
  expect(zone.status === 200 && Array.isArray(zone.data), `zone scores ${zone.status}`);
  const denied = await api(`/api/scores/zone/${me.supervisor.zone.id}`, { token: tokens.miner });
  expect(denied.status === 403, `miners must not see risk bands, got ${denied.status}`);
  return `rank=${mine.data.rank} score=${mine.data.score}`;
});

await step('rewards: publish is idempotent', async () => {
  const month = new Date().toISOString().slice(0, 7);
  const a = await api(`/api/rewards/publish?month=${month}`, { token: tokens.admin, method: 'POST' });
  const b = await api(`/api/rewards/publish?month=${month}`, { token: tokens.admin, method: 'POST' });
  expect(a.status === 200 && b.status === 200, `publish ${a.status}/${b.status}`);
  expect(b.data.created === 0, `second publish created ${b.data.created}`);
  const denied = await api(`/api/rewards/publish?month=${month}`, { token: tokens.miner, method: 'POST' });
  expect(denied.status === 403, `miner publish gave ${denied.status}`);
});

await step('admin normal mode: SLA, hazard audit, report PDF', async () => {
  expect((await api('/api/admin/sla', { token: tokens.admin })).status === 200, 'sla');
  expect((await api('/api/admin/hazard-audit', { token: tokens.admin })).status === 200, 'hazard-audit');
  const g = await api('/api/admin/reports/generate', { token: tokens.admin, method: 'POST', json: {} });
  expect(g.status === 201, `generate ${g.status} ${JSON.stringify(g.data?.error ?? '')}`);
  const u = await api(`/api/admin/reports/${g.data.id}/url`, { token: tokens.admin });
  expect(u.status === 200 && u.data.url, `report url ${u.status}`);
});

await step('contacts: unsafe dial targets are refused, safe calls are dry-run', async () => {
  const list = await api('/api/contacts', { token: tokens.admin });
  expect(list.status === 200 && list.data.length >= 5, `list ${list.status}`);
  const first = list.data[0];
  expect(first.dialE164 && first.displayNumber, 'admin must see dialE164 and displayNumber');
  for (const bad of ['+91112', '+91100', '+91108', '+1911']) {
    const r = await api(`/api/contacts/${first.id}`, { token: tokens.admin, method: 'PUT', json: { dialE164: bad } });
    expect(r.status === 400 && r.data?.error?.code === 'UNSAFE_DIAL_TARGET', `${bad} gave ${r.status} ${r.data?.error?.code}`);
  }
  const sup = await api('/api/contacts', { token: tokens.supervisor });
  expect(sup.status === 200 && !('dialE164' in sup.data[0]), 'supervisors must not receive dialE164');
  const call = await api(`/api/contacts/${first.id}/call`, { token: tokens.admin, method: 'POST', json: {} });
  expect(call.status === 200, `call ${call.status}`);
  expect(call.data.dryRun === true, 'TWILIO_DRY_RUN must be true for the smoke test');
});

await step('broadcast: supervisor limited to own zone; catch-up returns it', async () => {
  const since = new Date(Date.now() - 1000).toISOString();
  const a = await api('/api/broadcasts', { token: tokens.admin, method: 'POST', json: { text: 'Smoke test: shift briefing at 2 pm', priority: 'INFO', scope: 'ALL' } });
  expect(a.status === 201, `admin send ${a.status} ${JSON.stringify(a.data?.error ?? '')}`);
  const deny = await api('/api/broadcasts', { token: tokens.supervisor, method: 'POST', json: { text: 'Not allowed', priority: 'INFO', scope: 'ALL' } });
  expect(deny.status === 403, `supervisor ALL gave ${deny.status}`);
  const own = await api('/api/broadcasts', { token: tokens.supervisor, method: 'POST', json: { text: 'Smoke test: zone note', priority: 'INFO', scope: 'ZONE', zoneId: me.supervisor.zone.id } });
  expect(own.status === 201, `supervisor ZONE gave ${own.status}`);
  const tooLong = await api('/api/broadcasts', { token: tokens.admin, method: 'POST', json: { text: 'x'.repeat(281), priority: 'INFO', scope: 'ALL' } });
  expect(tooLong.status === 400, `281 chars gave ${tooLong.status}`);
  await sleep(1200);
  const c = await api(`/api/broadcasts?since=${encodeURIComponent(since)}`, { token: tokens.miner });
  expect(c.status === 200 && c.data.some((m) => m.text.includes('shift briefing')), 'catch-up missing the broadcast');
});

let crisisId;
await step('SOS activates crisis mode; admin sees roster, share token and routes', async () => {
  const r = await api('/api/sos', { token: tokens.miner, method: 'POST', json: { clientId: crypto.randomUUID(), lat: anchor.lat, lng: anchor.lng, accuracyM: 8, triggeredAt: new Date().toISOString() } });
  expect(r.status === 201, `sos ${r.status}`);
  const active = await until(async () => {
    const x = await api('/api/crisis/active', { token: tokens.admin });
    return x.data?.active ? x.data : null;
  }, { tries: 10, every: 1000, what: 'crisis activation' });
  crisisId = active.crisis.crisisId;
  expect(active.crisis.shareToken && active.roster?.length >= 1, 'admin view missing share token or roster');
  const routes = await until(async () => {
    const x = await api(`/api/crisis/${crisisId}/routes`, { token: tokens.admin });
    return x.status === 200 && x.data.features?.length ? x.data : null;
  }, { tries: 10, every: 1000, what: 'routes' });
  const mine = routes.features.filter((f) => f.properties.workerId === me.miner.user.id);
  expect(mine.length >= 1, 'no route for the SOS worker');
  const miner = await api('/api/crisis/active', { token: tokens.miner });
  expect(miner.data.active && !miner.data.crisis.shareToken, 'miners must not receive the share token');
  return `routes=${routes.features.length} sosWorkerRoutes=${mine.length}`;
});

await step('public tracking page works with the token, no auth, no scripts', async () => {
  const active = await api('/api/crisis/active', { token: tokens.admin });
  const res = await fetch(`${BASE}/public/track/${active.data.crisis.shareToken}`);
  const html = await res.text();
  expect(res.status === 200 && html.includes('emergency in progress') && !/<script/i.test(html), `page ${res.status}`);
});

await step('crisis tools: accounted, block a tunnel, recompute, assign route', async () => {
  const active = await api('/api/crisis/active', { token: tokens.admin });
  const w = active.data.roster.find((x) => x.userId === me.miner.user.id) ?? active.data.roster[0];
  const acc = await api(`/api/crisis/${crisisId}/accounted`, { token: tokens.admin, method: 'POST', json: { workerId: w.userId, status: 'SAFE' } });
  expect(acc.status === 200, `accounted ${acc.status}`);
  const blk = await api(`/api/crisis/${crisisId}/edges/T-J0-J1`, { token: tokens.admin, method: 'PATCH', json: { blocked: true } });
  expect(blk.status === 200, `block ${blk.status}`);
  const rc = await api(`/api/crisis/${crisisId}/recompute`, { token: tokens.admin, method: 'POST' });
  expect(rc.status === 200, `recompute ${rc.status}`);
  await api(`/api/crisis/${crisisId}/edges/T-J0-J1`, { token: tokens.admin, method: 'PATCH', json: { blocked: false } });
  const as = await api(`/api/crisis/${crisisId}/assign-route`, { token: tokens.admin, method: 'POST', json: { workerId: w.userId, exitId: 'X-INCL' } });
  expect([200, 409].includes(as.status), `assign ${as.status}`);
  const sup = await api(`/api/crisis/${crisisId}/recompute`, { token: tokens.supervisor, method: 'POST' });
  expect(sup.status === 403, `supervisor recompute gave ${sup.status}`);
});

await step('resolve: incomplete checklist 400, false alarm 200, link expires, report exists', async () => {
  const bad = await api(`/api/crisis/${crisisId}/resolve`, { token: tokens.admin, method: 'POST', json: { falseAlarm: false, note: 'Attempt without the checklist', checklist: { allAccounted: true, hazardsContained: false } } });
  expect(bad.status === 400 && bad.data?.error?.code === 'CHECKLIST_INCOMPLETE', `incomplete gave ${bad.status} ${bad.data?.error?.code}`);
  const token = (await api('/api/crisis/active', { token: tokens.admin })).data.crisis.shareToken;
  const ok = await api(`/api/crisis/${crisisId}/resolve`, { token: tokens.admin, method: 'POST', json: { falseAlarm: true, note: 'Smoke test: closing the drill as a false alarm' } });
  expect(ok.status === 200, `resolve ${ok.status} ${JSON.stringify(ok.data?.error ?? '')}`);
  const page = await fetch(`${BASE}/public/track/${token}`);
  expect(page.status === 404, `expired link gave ${page.status}`);
  const after = await api('/api/crisis/active', { token: tokens.admin });
  expect(after.data.active === false, 'crisis still active');
  const rep = await until(async () => {
    const x = await api(`/api/crisis/${crisisId}/report`, { token: tokens.admin });
    return x.status === 200 && x.data.url ? x.data : null;
  }, { tries: 8, every: 1000, what: 'the crisis report' });
  return `report=${rep.report.id ?? rep.report._id}`;
});

const failed = printTable(rows);
process.exit(failed ? 1 : 0);
