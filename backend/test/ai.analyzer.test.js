import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { analyzeImage } from '../src/modules/ai-analyzer/analyzer.js';
import { aiConfig } from '../src/modules/ai-analyzer/config.js';
import { mockScenario } from '../src/modules/ai-analyzer/mock.js';
import { prepare } from '../src/modules/ai-analyzer/image.prep.js';
import { ppeResponseSchema, hazardResponseSchema } from '../src/modules/ai-analyzer/schemas.js';

async function jpeg(seed = 0, size = 800) {
  const raw = Buffer.alloc(size * size * 3);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const v = ((x >> 4) + (y >> 4)) % 2 ? 200 - seed : 70 + seed;
    const i = (y * size + x) * 3;
    raw[i] = raw[i + 1] = raw[i + 2] = v;
  }
  return sharp(raw, { raw: { width: size, height: size, channels: 3 } }).jpeg({ quality: 90 }).toBuffer();
}

const ctx = { zoneCode: 'Z-B', requiredPpe: ['HELMET', 'REFLECTIVE_VEST', 'SAFETY_BOOTS', 'GLOVES'], category: 'ELECTRICAL' };

test('without an API key the analyser degrades to NEEDS_MANUAL_REVIEW and never throws', async () => {
  const cfg = aiConfig({ ML_MODE: 'hybrid', GEMINI_API_KEY: '' });
  const r = await analyzeImage({ mode: 'ppe', imageBuffer: await jpeg(), context: ctx }, cfg);
  assert.equal(r.overallVerdict, 'NEEDS_MANUAL_REVIEW');
  assert.equal(r.error.code, 'NO_API_KEY');
  assert.equal(r.summary, 'AI could not assess this photo — manual review required');
  assert.ok(r.items.filter((i) => i.required).every((i) => i.status === 'UNCERTAIN'));
});

test('hazard failure policy: severity null with an error', async () => {
  const r = await analyzeImage({ mode: 'hazard', imageBuffer: await jpeg(), context: ctx }, aiConfig({ ML_MODE: 'hybrid', GEMINI_API_KEY: '' }));
  assert.equal(r.severity, null);
  assert.ok(r.error);
});

test('an invalid image degrades instead of throwing', async () => {
  const r = await analyzeImage({ mode: 'ppe', imageBuffer: Buffer.from('not an image'), context: ctx }, aiConfig({ ML_MODE: 'mock' }));
  assert.equal(r.overallVerdict, 'NEEDS_MANUAL_REVIEW');
  assert.equal(r.error.code, 'IMAGE_INVALID');
});

test('mock mode is deterministic from the image sha256 and covers every scenario and never reports an emergency', async () => {
  const cfg = aiConfig({ ML_MODE: 'mock' });
  const seen = new Set();
  for (let seed = 0; seed < 40 && seen.size < 3; seed++) {
    const buf = await jpeg(seed);
    const { sha256 } = await prepare(buf);
    const a = await analyzeImage({ mode: 'ppe', imageBuffer: buf, context: ctx }, cfg);
    const b = await analyzeImage({ mode: 'ppe', imageBuffer: buf, context: ctx }, cfg);
    assert.deepEqual({ ...a, latencyMs: 0 }, { ...b, latencyMs: 0 });
    const sc = mockScenario(sha256);
    seen.add(sc);
    if (sc === 'compliant') assert.equal(a.overallVerdict, 'COMPLIANT');
    if (sc === 'no_helmet') assert.equal(a.overallVerdict, 'NON_COMPLIANT');
    if (sc === 'needs_review') assert.equal(a.overallVerdict, 'NEEDS_MANUAL_REVIEW');
    assert.equal(a.emergency.detected, false);
    assert.notEqual(sc, 'emergency');
  }
  assert.ok(seen.size >= 3, `only saw ${[...seen]}`);
});

test('image prep rejects tiny images and non-images', async () => {
  await assert.rejects(prepare(Buffer.from('xx')), /JPEG or PNG/);
  await assert.rejects(prepare(await jpeg(0, 300)), /too small/);
  const ok = await prepare(await jpeg(0, 2000));
  assert.ok(Math.max(ok.width, ok.height) <= 1536);
});

test('response schemas use only the allowed JSON-Schema keywords and require every top-level field', () => {
  const allowed = new Set(['type', 'properties', 'required', 'enum', 'items', 'minimum', 'maximum']);
  const walk = (s) => {
    for (const k of Object.keys(s)) assert.ok(allowed.has(k), `forbidden keyword ${k}`);
    if (s.properties) for (const v of Object.values(s.properties)) walk(v);
    if (s.items) walk(s.items);
  };
  walk(ppeResponseSchema);
  walk(hazardResponseSchema);
  assert.deepEqual([...ppeResponseSchema.required].sort(), Object.keys(ppeResponseSchema.properties).sort());
  assert.deepEqual([...hazardResponseSchema.required].sort(), Object.keys(hazardResponseSchema.properties).sort());
});
