import test from 'node:test';
import assert from 'node:assert/strict';
import { buildLayout, layoutStats } from '../seed/build_layout.js';

test('layout meets structural requirements', () => {
  const g = buildLayout({ lat: 23.746, lng: 86.415 });
  const s = layoutStats(g);
  assert.ok(s.tunnels >= 30);
  assert.equal(s.exits, 3);
  assert.equal(s.refuges, 1);
  assert.equal(s.zones, 3);
  const t = g.features.find((f) => f.properties.kind === 'tunnel' && f.properties.id === 'T-J0-J1');
  assert.equal(t.properties.slopePct, 1.5);
  assert.equal(t.geometry.type, 'LineString');
});

test('add-on X4: every tunnel has lightLux, two unlit trunk spans, aid points on junctions, version 2', async () => {
  const { AID_POINTS, DARK_TUNNELS, LAYOUT_VERSION, validateAids } = await import('../seed/build_layout.js');
  const g = buildLayout({ lat: 23.746, lng: 86.415 });
  const tunnels = g.features.filter((f) => f.properties.kind === 'tunnel');
  assert.ok(tunnels.every((t) => typeof t.properties.lightLux === 'number' && t.properties.lightLux >= 0 && t.properties.lightLux <= 400));
  assert.deepEqual(tunnels.filter((t) => t.properties.lightLux === 0).map((t) => t.properties.id).sort(), [...DARK_TUNNELS].sort());
  const aids = g.features.filter((f) => f.properties.kind === 'aid');
  assert.equal(aids.length, AID_POINTS.length);
  assert.equal(layoutStats(g).aids, 16);
  assert.deepEqual([...new Set(aids.map((a) => a.properties.aidType))].sort(), ['FIRE_EXTINGUISHER', 'FIRST_AID', 'PHONE', 'SCSR_CACHE', 'TOOL_STATION']);
  assert.ok(LAYOUT_VERSION >= 2);
  const moved = structuredClone(g);
  moved.features.find((f) => f.properties.kind === 'aid').geometry.coordinates[1] += 0.001; // ~111 m
  assert.throws(() => validateAids(moved), /more than 10 m/);
});
