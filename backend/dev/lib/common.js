// Shared helpers for dev scripts (simulators, smoke tests). Not used by the server.
import 'dotenv/config';

export const BASE = process.env.API_BASE || `http://127.0.0.1:${process.env.PORT || 4000}`;

export async function emit(event, rooms, data) {
  const res = await fetch(`${BASE}/dev/emit`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ event, rooms, data }) });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`emit ${event} failed: ${res.status} ${JSON.stringify(j)}`);
  return j;
}

export async function bus(event, data) {
  const res = await fetch(`${BASE}/dev/bus`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ event, data }) });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`bus ${event} failed: ${res.status} ${JSON.stringify(j)}`);
  return j;
}

export async function api(path, { token, method = 'GET', json, form, headers = {} } = {}) {
  const h = { ...headers };
  if (token) h.authorization = `Bearer ${token}`;
  let body;
  if (json !== undefined) {
    h['content-type'] = 'application/json';
    body = JSON.stringify(json);
  } else if (form) {
    body = form;
  }
  const res = await fetch(`${BASE}${path}`, { method, headers: h, body });
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { status: res.status, data };
}

export function printTable(rows) {
  const w = Math.max(...rows.map((r) => r.name.length), 10);
  for (const r of rows) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(w)}  ${r.detail ?? ''}`);
  const failed = rows.filter((r) => !r.ok).length;
  console.log(`\n${rows.length - failed}/${rows.length} passed`);
  return failed;
}

export async function connectMongo() {
  const { default: mongoose } = await import('mongoose');
  await mongoose.connect(process.env.MONGODB_URI, { dbName: process.env.MONGODB_DB || 'mine_guardian', serverSelectionTimeoutMS: 8000 });
  return mongoose;
}
