// I.1 contract check. Offline part: socket events and enums are identical in the backend contract and the Flutter contract.
// Live part (only if the server answers): every route in routes.md (+ routes.additive.md) exists; an unauthenticated call must not return the router's 404.
// Usage: node dev/contract-check.js        (start the server first for the live part; exits non-zero on any FAIL)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SOCKET_EVENTS, BUS_EVENTS } from '../src/contracts/events.js';
import * as ENUMS from '../src/contracts/enums.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFileSync(path.join(here, ...p), 'utf8');
const BASE = process.env.API_BASE || `http://localhost:${process.env.PORT || 4000}`;
const rows = [];
const check = (name, ok, detail = '') => rows.push({ name, ok, detail });
const warn = (name, detail) => rows.push({ name, ok: true, detail: `WARN ${detail}` });

const dartSocket = read('..', '..', 'mobile', 'lib', 'contracts', 'socket_events.dart');
const dartStrings = (src) => [...src.matchAll(/static const \w+ = '([^']+)'/g)].map((m) => m[1]);
const diff = (a, b) => ({ onlyA: a.filter((x) => !b.includes(x)), onlyB: b.filter((x) => !a.includes(x)) });

// ---- socket events ----
{
  const dartAll = dartStrings(dartSocket);
  const server = SOCKET_EVENTS.serverToClient;
  const client = SOCKET_EVENTS.clientToServer;
  const missing = [...server, ...client].filter((e) => !dartAll.includes(e));
  check('socket events: every backend event exists in Dart', missing.length === 0, missing.join(', '));
  const listBlock = dartSocket.match(/serverToClient = <String>\[([\s\S]*?)\];/)?.[1] ?? '';
  const names = [...dartSocket.matchAll(/static const (\w+) = '([^']+)'/g)].reduce((m, x) => ((m[x[1]] = x[2]), m), {});
  const dartServer = listBlock.split(',').map((s) => s.trim()).filter(Boolean).map((n) => names[n]);
  const d = diff(server, dartServer);
  check('socket events: Dart serverToClient list equals the backend list', d.onlyA.length === 0 && d.onlyB.length === 0, JSON.stringify(d));
}
check('bus events: 10 v1 names + 2 add-on names', BUS_EVENTS.length === 12, `${BUS_EVENTS.length}`);

// ---- enums ----
{
  const dart = read('..', '..', 'mobile', 'lib', 'contracts', 'enums.dart');
  const camel = (s) => s.toLowerCase().split('_').map((w) => w[0].toUpperCase() + w.slice(1)).join('');
  const names = Object.keys(ENUMS).filter((k) => Array.isArray(ENUMS[k]) || (ENUMS[k] && typeof ENUMS[k] === 'object' && !Array.isArray(ENUMS[k]) && Object.values(ENUMS[k]).every((v) => typeof v === 'string')));
  let compared = 0;
  for (const key of names.filter((k) => /^[A-Z_]+$/.test(k))) {
    const values = Array.isArray(ENUMS[key]) ? ENUMS[key] : Object.values(ENUMS[key]);
    if (!values.length || values.some((v) => typeof v !== 'string' || /[a-z]/.test(v) && key !== 'ROLE' && key !== 'USER_STATUS' && key !== 'SHIFT' && key !== 'REVIEW_STATUS')) continue;
    const cls = camel(key);
    const m = dart.match(new RegExp(`enum ${cls} implements WireEnum \\{([\\s\\S]*?)\\n\\}`));
    if (!m) { warn(`enum ${key}`, `no Dart enum ${cls}`); continue; }
    const wires = [...m[1].matchAll(/\w+\('([^']+)'/g)].map((x) => x[1]);
    const d = diff(values, wires);
    compared += 1;
    check(`enum ${key} == Dart ${cls}`, d.onlyA.length === 0 && d.onlyB.length === 0, JSON.stringify(d));
  }
  check('enums: at least 15 compared', compared >= 15, `${compared}`);
}

// ---- live routes ----
const spec = [...read('..', 'src', 'contracts', 'routes.md').matchAll(/^(GET|POST|PUT|PATCH|DELETE) (\S+)/gm), ...read('..', 'src', 'contracts', 'routes.additive.md').matchAll(/^(GET|POST|PUT|PATCH|DELETE) (\S+)/gm)].map((m) => ({ method: m[1], path: m[2] }));
let alive = false;
try {
  alive = (await fetch(`${BASE}/api/health`, { signal: AbortSignal.timeout(3000) })).ok;
} catch {
  alive = false;
}
if (!alive) {
  warn('live routes', `server not reachable at ${BASE}: skipped ${spec.length} route probes (start it and re-run)`);
} else {
  const dummy = '000000000000000000000000';
  for (const r of spec) {
    const url = `${BASE}${r.path.replace(/:\w+/g, dummy)}`;
    const init = { method: r.method, headers: { 'content-type': 'application/json' }, body: ['GET', 'DELETE'].includes(r.method) ? undefined : '{}' };
    const res = await fetch(url, init);
    const body = await res.json().catch(() => ({}));
    const routeMissing = res.status === 404 && /^Route not found/.test(body?.error?.message ?? '');
    const isPublic = r.path.startsWith('/public/') || r.path === '/api/health' || r.path === '/api/zones' || r.path === '/api/layout';
    check(`${r.method} ${r.path}`, !routeMissing && (isPublic || res.status !== 200), `status ${res.status}`);
  }
}

const w = Math.max(...rows.map((r) => r.name.length), 10);
for (const r of rows) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(w)}  ${r.detail}`);
const failed = rows.filter((r) => !r.ok).length;
console.log(`\n${rows.length - failed}/${rows.length} passed`);
process.exit(failed ? 1 : 0);
