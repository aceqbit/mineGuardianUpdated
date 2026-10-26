// Synthetic mine layout builder. Local metre grid (x east, y north) centred on the anchor.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { localToLatLng, pointInPolygon } from '../src/core/geo.js';

const XS = [-300, -180, -60, 60, 180, 300];

/** Bumped whenever the generated layout changes, so phones (ETag) and the rerouter reload it. v2: lightLux + aid points. */
export const LAYOUT_VERSION = 2;

/** Add-on X4: lighting per tunnel (lux). Two trunk spans are unlit so the "most light" route has something to avoid. */
const LUX = { trunk: 150, crossCut: 60, return: 20 };
export const DARK_TUNNELS = new Set(['T-J3-J4', 'T-J6-J7']);

/** Add-on X4 aid points, each on a junction: first aid, tool stations, a phone at every exit, self-rescuer caches, extinguishers every 120 m of trunk. */
export const AID_POINTS = [
  { id: 'AID-FA-J2', aidType: 'FIRST_AID', name: 'First aid station J2', node: 'J2' },
  { id: 'AID-FA-J8', aidType: 'FIRST_AID', name: 'First aid station J8', node: 'J8' },
  { id: 'AID-TS-N2', aidType: 'TOOL_STATION', name: 'Tool station N2', node: 'N2' },
  { id: 'AID-TS-S4', aidType: 'TOOL_STATION', name: 'Tool station S4', node: 'S4' },
  { id: 'AID-PH-J0', aidType: 'PHONE', name: 'Phone at Main Shaft', node: 'J0' },
  { id: 'AID-PH-N5', aidType: 'PHONE', name: 'Phone at Incline Adit', node: 'N5' },
  { id: 'AID-PH-S2', aidType: 'PHONE', name: 'Phone at Return Air Shaft', node: 'S2' },
  { id: 'AID-SC-J5', aidType: 'SCSR_CACHE', name: 'Self-rescuer cache J5', node: 'J5' },
  { id: 'AID-SC-N3', aidType: 'SCSR_CACHE', name: 'Self-rescuer cache N3', node: 'N3' },
  { id: 'AID-SC-S1', aidType: 'SCSR_CACHE', name: 'Self-rescuer cache S1', node: 'S1' },
  ...['J0', 'J2', 'J4', 'J6', 'J8', 'J10'].map((n) => ({ id: `AID-FE-${n}`, aidType: 'FIRE_EXTINGUISHER', name: `Extinguisher ${n}`, node: n })),
];

export const ZONE_RECTS = {
  'Z-A': { x: [-330, -110], y: [-150, 150] },
  'Z-B': { x: [-110, 110], y: [-150, 150] },
  'Z-C': { x: [110, 330], y: [-150, 150] },
};

export function buildLayout(anchor) {
  const nodes = {}; // id -> {x,y}
  for (let i = 0; i <= 10; i++) nodes[`J${i}`] = { x: -300 + i * 60, y: 0 };
  XS.forEach((x, i) => {
    nodes[`N${i}`] = { x, y: 120 };
    nodes[`S${i}`] = { x, y: -120 };
  });

  const ll = (n) => {
    const p = localToLatLng(anchor, n.x, n.y);
    return [p.lng, p.lat];
  };

  const features = [];
  const tunnels = [];
  const addTunnel = (from, to, widthM, capacity, slopePct, airway, lux) => {
    const id = `T-${from}-${to}`;
    const lightLux = DARK_TUNNELS.has(id) ? 0 : lux;
    tunnels.push({ id, from, to });
    features.push({
      type: 'Feature',
      properties: { kind: 'tunnel', id, fromNode: from, toNode: to, widthM, capacity, slopePct, airway, status: 'open', lightLux },
      geometry: { type: 'LineString', coordinates: [ll(nodes[from]), ll(nodes[to])] },
    });
  };

  for (let i = 0; i < 10; i++) addTunnel(`J${i}`, `J${i + 1}`, 3.5, 20, 1.5, 'intake', LUX.trunk);
  for (let i = 0; i < 5; i++) addTunnel(`N${i}`, `N${i + 1}`, 2.8, 12, -1.0, 'return', LUX.return);
  for (let i = 0; i < 5; i++) addTunnel(`S${i}`, `S${i + 1}`, 2.8, 12, -1.0, 'return', LUX.return);
  XS.forEach((_x, i) => {
    const j = `J${i * 2}`;
    addTunnel(`N${i}`, j, 2.5, 10, 3.0, 'intake', LUX.crossCut); // north -> south
    addTunnel(j, `S${i}`, 2.5, 10, 3.0, 'intake', LUX.crossCut);
  });

  for (const id of Object.keys(nodes)) {
    features.push({ type: 'Feature', properties: { kind: 'junction', id }, geometry: { type: 'Point', coordinates: ll(nodes[id]) } });
  }

  const exits = [
    { id: 'X-MAIN', name: 'Main Shaft', exitType: 'shaft', node: 'J0' },
    { id: 'X-INCL', name: 'Incline Adit', exitType: 'incline', node: 'N5' },
    { id: 'X-RET', name: 'Return Air Shaft', exitType: 'shaft', node: 'S2' },
  ];
  for (const ex of exits) {
    features.push({
      type: 'Feature',
      properties: { kind: 'exit', id: ex.id, name: ex.name, exitType: ex.exitType, node: ex.node },
      geometry: { type: 'Point', coordinates: ll(nodes[ex.node]) },
    });
  }
  features.push({
    type: 'Feature',
    properties: { kind: 'refuge', id: 'RC-1', name: 'Refuge Chamber RC-1', capacity: 25, node: 'J7' },
    geometry: { type: 'Point', coordinates: ll(nodes.J7) },
  });

  for (const a of AID_POINTS) {
    features.push({
      type: 'Feature',
      properties: { kind: 'aid', id: a.id, aidType: a.aidType, name: a.name, node: a.node },
      geometry: { type: 'Point', coordinates: ll(nodes[a.node]) },
    });
  }

  for (const [code, r] of Object.entries(ZONE_RECTS)) {
    const [x0, x1] = r.x;
    const [y0, y1] = r.y;
    const ring = [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]].map(([x, y]) => ll({ x, y }));
    features.unshift({ type: 'Feature', properties: { kind: 'zone', code }, geometry: { type: 'Polygon', coordinates: [ring] } });
  }

  const geojson = { type: 'FeatureCollection', features };
  validateLayout(geojson, nodes, tunnels, exits);
  validateAids(geojson);
  return geojson;
}

export function validateLayout(geojson, nodes, tunnels, exits) {
  const adj = new Map(Object.keys(nodes).map((k) => [k, []]));
  for (const t of tunnels) {
    adj.get(t.from).push(t.to);
    adj.get(t.to).push(t.from);
  }
  const reach = (start) => {
    const seen = new Set([start]);
    const q = [start];
    while (q.length) {
      const c = q.shift();
      for (const n of adj.get(c)) if (!seen.has(n)) (seen.add(n), q.push(n));
    }
    return seen;
  };
  const all = Object.keys(nodes);
  const first = reach(all[0]);
  if (first.size !== all.length) throw new Error('Layout invalid: graph is not connected');
  const exitNodes = new Set(exits.map((e) => e.node));
  for (const j of all) {
    const r = reach(j);
    const n = [...exitNodes].filter((x) => r.has(x)).length;
    if (n < 2) throw new Error(`Layout invalid: junction ${j} reaches fewer than 2 exits`);
  }
  for (const z of geojson.features.filter((f) => f.properties.kind === 'zone')) {
    const poly = z.geometry;
    const count = geojson.features.filter(
      (f) => f.properties.kind === 'junction' && pointInPolygon({ lng: f.geometry.coordinates[0], lat: f.geometry.coordinates[1] }, poly),
    ).length;
    if (count < 3) throw new Error(`Layout invalid: zone ${z.properties.code} has fewer than 3 junctions`);
  }
}

/** Every aid point names a known junction and sits within 10 m of it (CLAUDE.md section 23.4). */
export function validateAids(geojson) {
  const junctions = new Map(geojson.features.filter((f) => f.properties.kind === 'junction').map((f) => [f.properties.id, f.geometry.coordinates]));
  for (const f of geojson.features.filter((x) => x.properties.kind === 'aid')) {
    const j = junctions.get(f.properties.node);
    if (!j) throw new Error(`Layout invalid: aid ${f.properties.id} names unknown junction ${f.properties.node}`);
    const [lng, lat] = f.geometry.coordinates;
    const dy = (lat - j[1]) * 111320;
    const dx = (lng - j[0]) * 111320 * Math.cos((lat * Math.PI) / 180);
    if (Math.hypot(dx, dy) > 10) throw new Error(`Layout invalid: aid ${f.properties.id} is more than 10 m from junction ${f.properties.node}`);
  }
}

export function layoutStats(geojson) {
  const c = (k) => geojson.features.filter((f) => f.properties.kind === k).length;
  return { tunnels: c('tunnel'), junctions: c('junction'), exits: c('exit'), refuges: c('refuge'), zones: c('zone'), aids: c('aid') };
}

// CLI: npm run layout
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const lat = Number(process.env.DEMO_ANCHOR_LAT ?? 23.746);
  const lng = Number(process.env.DEMO_ANCHOR_LNG ?? 86.415);
  const g = buildLayout({ lat, lng });
  const out = path.join(path.dirname(fileURLToPath(import.meta.url)), 'sample', 'mine_layout.geojson');
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify(g, null, 2));
  const s = layoutStats(g);
  console.log(`Layout written to ${out}\nnodes=${s.junctions} edges=${s.tunnels} exits=${s.exits} refuges=${s.refuges} zones=${s.zones} aids=${s.aids}`);
}
