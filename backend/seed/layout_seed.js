import { env } from '../src/config/env.js';
import { buildLayout } from './build_layout.js';
import { MineLayout } from '../src/models/MineLayout.js';
import { Zone } from '../src/models/Zone.js';

export const MINE = 'MG Demo Colliery';
export const SHIFT_WINDOWS = [
  { shift: 'A', start: '06:00', end: '14:00' },
  { shift: 'B', start: '14:00', end: '22:00' },
  { shift: 'C', start: '22:00', end: '06:00' },
];
export const ZONES = [
  { code: 'Z-A', name: 'Zone A — West Panel', requiredPpe: ['HELMET', 'CAP_LAMP', 'REFLECTIVE_VEST', 'SAFETY_BOOTS', 'GLOVES', 'SELF_RESCUER'] },
  { code: 'Z-B', name: 'Zone B — Central Panel', requiredPpe: ['HELMET', 'REFLECTIVE_VEST', 'SAFETY_BOOTS', 'GLOVES'] },
  { code: 'Z-C', name: 'Zone C — East Panel', requiredPpe: ['HELMET', 'CAP_LAMP', 'REFLECTIVE_VEST', 'SAFETY_BOOTS', 'GLOVES', 'SELF_RESCUER', 'DUST_MASK', 'EAR_PROTECTION', 'EYE_PROTECTION'] },
];

const polygonOf = (geojson, code) => geojson.features.find((f) => f.properties.kind === 'zone' && f.properties.code === code).geometry;

/** Layout v1 and the three zones. Mongo only: needs no Firebase credential, safe to run any number of times. */
export async function seedLayoutAndZones() {
  const geojson = buildLayout({ lat: env.DEMO_ANCHOR_LAT, lng: env.DEMO_ANCHOR_LNG });
  await MineLayout.updateOne(
    { version: 1 },
    { $set: { version: 1, anchor: { lat: env.DEMO_ANCHOR_LAT, lng: env.DEMO_ANCHOR_LNG }, geojson } },
    { upsert: true },
  );
  const zones = {};
  for (const z of ZONES) {
    zones[z.code] = await Zone.findOneAndUpdate(
      { code: z.code },
      { $set: { ...z, mineName: MINE, polygon: polygonOf(geojson, z.code), shiftWindows: SHIFT_WINDOWS } },
      { upsert: true, new: true },
    );
  }
  return { geojson, zones };
}
