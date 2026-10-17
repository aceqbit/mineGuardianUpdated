import test from 'node:test';
import assert from 'node:assert/strict';
import { parseOrs, planEmits, presenceChanges, presenceOf, snapshotScope, toWire } from '../src/modules/tracking/tracking.logic.js';

const now = Date.parse('2026-10-17T10:00:00Z');
const at = (sec) => new Date(now - sec * 1000).toISOString();
const e = (userId, zoneId, ageSec, extra = {}) => ({ userId, name: userId, employeeId: userId.toUpperCase(), role: 'miner', zoneId, lat: 23.7, lng: 86.4, accuracyM: 5, ts: at(ageSec), ...extra });

test('presence bands', () => {
  assert.equal(presenceOf(at(5), now, 30, 120), 'LIVE');
  assert.equal(presenceOf(at(30), now, 30, 120), 'STALE');
  assert.equal(presenceOf(at(119), now, 30, 120), 'STALE');
  assert.equal(presenceOf(at(120), now, 30, 120), 'OFFLINE');
  assert.equal(presenceOf(null, now, 30, 120), 'OFFLINE');
});

test('emits: admin gets everyone, each zone supervisor room only its own people', () => {
  const plan = planEmits([e('m1', 'ZA', 1), e('m2', 'ZA', 2), e('m3', 'ZB', 3)], now, 30, 120);
  const byRoom = Object.fromEntries(plan.map((p) => [p.room, p.positions.map((x) => x.userId)]));
  assert.deepEqual(byRoom['role:admin'], ['m1', 'm2', 'm3']);
  assert.deepEqual(byRoom['zone:ZA:supervisors'], ['m1', 'm2']);
  assert.deepEqual(byRoom['zone:ZB:supervisors'], ['m3']);
  assert.equal(Object.keys(byRoom).length, 3);
  assert.deepEqual(planEmits([], now, 30, 120), []);
});

test('wire shape carries the fused fields and defaults', () => {
  const w = toWire(e('m1', 'ZA', 1, { headingDeg: 90, source: 'PDR', tunnelId: 'T-J1-J2' }), now, 30, 120);
  assert.equal(w.presence, 'LIVE');
  assert.equal(w.source, 'PDR');
  assert.equal(w.tunnelId, 'T-J1-J2');
  assert.equal(toWire(e('m2', 'ZA', 1), now, 30, 120).source, 'GPS');
  assert.equal(toWire(e('m2', 'ZA', 1), now, 30, 120).speedMps, null);
});

test('presence sweep reports each band change once', () => {
  const last = new Map();
  const list = [e('m1', 'ZA', 5)];
  assert.deepEqual(presenceChanges(list, last, now, 30, 120), ['m1']);
  assert.deepEqual(presenceChanges(list, last, now, 30, 120), []);
  assert.deepEqual(presenceChanges(list, last, now + 40_000, 30, 120), ['m1']);
  assert.equal(last.get('m1'), 'STALE');
});

test('snapshot scope: supervisor own zone only, miners refused', () => {
  assert.deepEqual(snapshotScope({ role: 'admin' }, undefined), { zoneId: null });
  assert.deepEqual(snapshotScope({ role: 'supervisor', zoneId: 'ZA' }, undefined), { zoneId: 'ZA' });
  assert.deepEqual(snapshotScope({ role: 'supervisor', zoneId: 'ZA' }, 'ZB'), { error: 'FORBIDDEN_SCOPE' });
  assert.deepEqual(snapshotScope({ role: 'miner', zoneId: 'ZA' }, 'ZA'), { error: 'FORBIDDEN_ROLE' });
});

test('ORS parse', () => {
  const ok = parseOrs({ features: [{ properties: { summary: { distance: 812.4, duration: 584.6 } }, geometry: { coordinates: [[86.41, 23.74], [86.42, 23.75]] } }] });
  assert.deepEqual(ok, { distanceM: 812, durationSec: 585, coordinates: [[86.41, 23.74], [86.42, 23.75]] });
  assert.equal(parseOrs({}), null);
  assert.equal(parseOrs({ features: [{ properties: { summary: {} }, geometry: { coordinates: [[1, 2]] } }] }), null);
});
