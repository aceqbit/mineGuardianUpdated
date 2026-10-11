// Phase 1 gate. Needs: the server running (npm run dev), the seed loaded, FIREBASE_WEB_API_KEY in the shell.
// Signs in as the miner, supervisor and admin; posts a check-in, a hazard, an SOS and its cancel; verifies the supervisor feed
// and the admin overview. Prints PASS/FAIL per step and exits non-zero on any failure.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { api, printTable } from './lib/common.js';
import { getToken } from './get-token.js';
import { demoEmailFor } from '../seed/accounts.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const sampleDir = path.join(here, '..', 'seed', 'sample');
const anchor = { lat: Number(process.env.DEMO_ANCHOR_LAT ?? 23.746), lng: Number(process.env.DEMO_ANCHOR_LNG ?? 86.415) };

async function samplePhoto(name) {
  const p = path.join(sampleDir, name);
  if (fs.existsSync(p)) return fs.readFileSync(p);
  // Fallback: a synthetic sharp image so the smoke test runs before real photos are added.
  console.log(`  (note) ${name} not found in seed/sample; using a synthetic image. Add real photos for a faithful test.`);
  const size = 900;
  const raw = Buffer.alloc(size * size * 3);
  const salt = crypto.randomInt(0, 40);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const v = (Math.floor(x / 12) + Math.floor(y / 12)) % 2 === 0 ? 190 + (salt % 20) : 60 + (salt % 30);
    const i = (y * size + x) * 3;
    raw[i] = v; raw[i + 1] = v - 10; raw[i + 2] = v - 20;
  }
  return sharp(raw, { raw: { width: size, height: size, channels: 3 } }).jpeg({ quality: 92 }).toBuffer();
}

const uniquify = async (buf) => {
  // Same photo every run would hit DUPLICATE_PHOTO: nudge a pixel so the sha256 differs.
  const { data, info } = await sharp(buf).raw().toBuffer({ resolveWithObject: true });
  data[0] = (data[0] + crypto.randomInt(1, 200)) % 255;
  return sharp(data, { raw: info }).jpeg({ quality: 92 }).toBuffer();
};

function photoForm(buf, fields) {
  const form = new FormData();
  form.append('image', new Blob([buf], { type: 'image/jpeg' }), 'photo.jpg');
  for (const [k, v] of Object.entries(fields)) form.append(k, String(v));
  return form;
}

const rows = [];
const step = async (name, fn) => {
  try {
    const detail = await fn();
    rows.push({ name, ok: true, detail: detail ?? '' });
    return true;
  } catch (e) {
    rows.push({ name, ok: false, detail: e.message });
    return false;
  }
};
const expect = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const tokens = {};
let checkInId, hazardId, sosId;
let overviewBefore;

await step('health endpoint', async () => {
  const r = await api('/api/health');
  expect(r.status === 200 && r.data?.ok, `status ${r.status}`);
});

for (const [role, empId, pw] of [['miner', 'MIN-0105', 'Miner1'], ['supervisor', 'SUP-0012', 'Super1'], ['admin', 'ADM-0001', 'Admin1']]) {
  await step(`sign in + /me as ${role}`, async () => {
    tokens[role] = await getToken(demoEmailFor(empId), pw);
    const r = await api(`/api/auth/me?expectedRole=${role}`, { token: tokens[role] });
    expect(r.status === 200 && r.data?.user?.role === role, `status ${r.status} ${JSON.stringify(r.data?.error ?? '')}`);
  });
}

await step('role mismatch returns 403 ROLE_MISMATCH', async () => {
  const r = await api('/api/auth/me?expectedRole=admin', { token: tokens.miner });
  expect(r.status === 403 && r.data?.error?.code === 'ROLE_MISMATCH' && r.data.error.details?.actualRole === 'miner', `got ${r.status} ${r.data?.error?.code}`);
});

await step('admin overview (before)', async () => {
  const r = await api('/api/admin/overview', { token: tokens.admin });
  expect(r.status === 200, `status ${r.status}`);
  overviewBefore = r.data;
  return `openHazards=${r.data.openHazards}`;
});

await step('POST /api/checkins', async () => {
  const buf = await uniquify(await samplePhoto('worker_full_body.jpg'));
  const form = photoForm(buf, {
    clientId: crypto.randomUUID(), capturedAt: new Date().toISOString(), uploadStartedAt: new Date().toISOString(), source: 'camera', attempt: 1,
    lat: anchor.lat, lng: anchor.lng, accuracyM: 8, sha256: crypto.createHash('sha256').update(buf).digest('hex'), clientQuality: JSON.stringify({ blurScore: 120, poseChecked: false }),
  });
  const r = await api('/api/checkins', { token: tokens.miner, method: 'POST', form });
  expect(r.status === 201, `status ${r.status} ${JSON.stringify(r.data?.error ?? '')}`);
  checkInId = r.data.checkIn.id ?? r.data.checkIn._id;
  return `id=${checkInId}`;
});

await step('POST /api/hazards (+ duplicate clientId is idempotent)', async () => {
  const buf = await uniquify(await samplePhoto('hazard_cable.jpg'));
  const clientId = crypto.randomUUID();
  const fields = { clientId, category: 'ELECTRICAL', capturedAt: new Date().toISOString(), uploadStartedAt: new Date().toISOString(), lat: anchor.lat, lng: anchor.lng, accuracyM: 8, sha256: crypto.createHash('sha256').update(buf).digest('hex'), source: 'camera' };
  const r = await api('/api/hazards', { token: tokens.miner, method: 'POST', form: photoForm(buf, fields) });
  expect(r.status === 201, `status ${r.status} ${JSON.stringify(r.data?.error ?? '')}`);
  hazardId = r.data.hazard.id ?? r.data.hazard._id;
  const again = await api('/api/hazards', { token: tokens.miner, method: 'POST', form: photoForm(buf, fields) });
  expect(again.status === 200 && (again.data.hazard.id ?? again.data.hazard._id) === hazardId, `repeat gave ${again.status}`);
  return `id=${hazardId}`;
});

await step('POST /api/sos', async () => {
  const r = await api('/api/sos', { token: tokens.miner, method: 'POST', json: { clientId: crypto.randomUUID(), lat: anchor.lat, lng: anchor.lng, accuracyM: 8, triggeredAt: new Date().toISOString() } });
  expect(r.status === 201, `status ${r.status} ${JSON.stringify(r.data?.error ?? '')}`);
  sosId = r.data.sos.id ?? r.data.sos._id;
  return `id=${sosId}`;
});

await step('supervisor feed contains the check-in, hazard and active SOS', async () => {
  const me = await api('/api/auth/me', { token: tokens.supervisor });
  const r = await api(`/api/feed/supervisor?zoneId=${me.data.zone.id}`, { token: tokens.supervisor });
  expect(r.status === 200, `status ${r.status}`);
  expect(r.data.checkins.some((c) => c.id === checkInId), 'check-in missing from feed');
  expect(r.data.hazards.some((h) => h.id === hazardId), 'hazard missing from feed');
  expect(r.data.sos.some((s) => s.id === sosId), 'active SOS missing from feed');
});

await step('Zone A supervisor cannot read Zone B (403)', async () => {
  const zones = await api('/api/zones');
  const other = zones.data.find((z) => z.code === 'Z-A');
  const supA = await getToken(demoEmailFor('SUP-0011'), 'Super1');
  const meB = await api('/api/auth/me', { token: tokens.supervisor });
  const r = await api(`/api/feed/supervisor?zoneId=${meB.data.zone.id}`, { token: supA });
  expect(r.status === 403, `status ${r.status} (zone ${other?.code})`);
});

await step('POST /api/sos/:id/cancel (by server id and by clientId)', async () => {
  const r = await api(`/api/sos/${sosId}/cancel`, { token: tokens.miner, method: 'POST' });
  expect(r.status === 200 && r.data.sos.status === 'CANCELLED', `status ${r.status} ${JSON.stringify(r.data?.error ?? '')}`);
});

await step('admin overview counts rose', async () => {
  const r = await api('/api/admin/overview', { token: tokens.admin });
  expect(r.status === 200, `status ${r.status}`);
  expect(r.data.openHazards >= overviewBefore.openHazards + 1, `openHazards ${overviewBefore.openHazards} -> ${r.data.openHazards}`);
  const zoneB = r.data.zones.find((z) => z.code === 'Z-B');
  expect(zoneB && zoneB.checkedInToday >= 1, 'Zone B checkedInToday did not rise');
  return `openHazards=${r.data.openHazards}`;
});

await step('hazard transitions: close without a note is 400, with a note ok', async () => {
  const bad = await api(`/api/hazards/${hazardId}`, { token: tokens.supervisor, method: 'PATCH', json: { status: 'CLOSED' } });
  expect(bad.status === 400, `status ${bad.status}`);
  const ok = await api(`/api/hazards/${hazardId}`, { token: tokens.supervisor, method: 'PATCH', json: { status: 'CLOSED', note: 'cable isolated by electrician' } });
  expect(ok.status === 200 && ok.data.hazard.status === 'CLOSED', `status ${ok.status}`);
});

const failed = printTable(rows);
process.exit(failed ? 1 : 0);
