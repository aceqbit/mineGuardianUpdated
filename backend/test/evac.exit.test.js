import test from 'node:test';
import assert from 'node:assert/strict';
import { isValidEvacExit, layoutExitIds } from '../src/modules/zones/evac.js';
import { buildLayout } from '../seed/build_layout.js';

const layout = { geojson: buildLayout({ lat: 23.746, lng: 86.415 }) };

test('layout exposes its exit ids', () => {
  const ids = layoutExitIds(layout);
  assert.equal(ids.length, 3);
});

test('null clears the choice, a real exit is accepted, an unknown one is refused', () => {
  const [first] = layoutExitIds(layout);
  assert.equal(isValidEvacExit(layout, null), true);
  assert.equal(isValidEvacExit(layout, undefined), true);
  assert.equal(isValidEvacExit(layout, first), true);
  assert.equal(isValidEvacExit(layout, 'EX-NOPE'), false);
  assert.equal(isValidEvacExit({ geojson: { features: [] } }, first), false);
});
