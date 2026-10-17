// Daily safety feed generation (CLAUDE.md section 23.6): Gemini + Google Search grounding, then a schema pass, then
// the source guard. Stored in `safety_feed` (one document per date + version).
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import mongoose from 'mongoose';
import { GoogleGenAI } from '@google/genai';
import { env } from '../../config/env.js';
import { logger } from '../../core/logger.js';
import { signedUrl, uploadBuffer } from '../../core/storage.js';
import { RESPONSE_SCHEMA, STEP1_PROMPT, STEP2_PROMPT, annotate, contextLines, guardItems, istDay, storyboards } from './feed.logic.js';

const col = () => mongoose.connection.collection('safety_feed');
const raw = (n) => mongoose.connection.collection(n);
let client = null;
const ai = () => (env.GEMINI_API_KEY ? (client ??= new GoogleGenAI({ apiKey: env.GEMINI_API_KEY })) : null);
const withTimeout = (p, ms, what) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(`${what} timed out`)), ms))]);

export const configured = () => Boolean(env.GEMINI_API_KEY) && env.SAFETY_FEED_ENABLED !== false;
export const allowlist = () => String(env.SAFETY_SOURCE_ALLOWLIST || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);

async function personalisation(date) {
  const since = new Date(Date.now() - 7 * 86_400_000);
  const [zones, hazards, missed] = await Promise.all([
    raw('zones').find({}, { projection: { code: 1, requiredPpe: 1 } }).sort({ code: 1 }).toArray().catch(() => []),
    raw('hazards').distinct('category', { status: { $in: ['OPEN', 'ACKNOWLEDGED'] } }).catch(() => []),
    raw('compliance_reviews')
      .aggregate([
        { $match: { 'decision.finalVerdict': 'NON_COMPLIANT', 'decision.decidedAt': { $gte: since } } },
        { $unwind: '$decision.items' },
        { $match: { 'decision.items.status': 'ABSENT' } },
        { $group: { _id: '$decision.items.key', n: { $sum: 1 } } },
        { $sort: { n: -1 } },
        { $limit: 3 },
      ])
      .toArray()
      .catch(() => []),
  ]);
  return contextLines({ date, zones, hazardCategories: hazards, missedPpe: missed.map((m) => m._id) });
}

export async function latest(date) {
  return col().find({ date }).sort({ version: -1 }).limit(1).next();
}

/** Signed links for stored clips (15 min). */
export async function withLinks(feed) {
  if (!feed) return feed;
  const videos = await Promise.all((feed.videos ?? []).map(async (v) => (v.kind === 'veo' && v.path ? { ...v, url: await signedUrl(v.path).catch(() => null) } : v)));
  const { _id, ...rest } = feed;
  return { ...rest, id: String(_id), videos };
}

async function veoClip(date, item) {
  const c = ai();
  if (!c || !env.VEO_MODEL) return null;
  const prompt = `A calm, realistic 8-second safety training clip for underground coal miners in India: ${item.title}. ${item.steps.slice(0, 3).join(' ')} No text on screen, no logos.`;
  let op = await withTimeout(c.models.generateVideos({ model: env.VEO_MODEL, prompt, config: { numberOfVideos: 1, aspectRatio: '16:9', durationSeconds: 8 } }), 30_000, 'veo start');
  const deadline = Date.now() + 5 * 60_000;
  while (!op.done) {
    if (Date.now() > deadline) throw new Error('veo timed out');
    await new Promise((r) => setTimeout(r, 10_000));
    op = await c.operations.getVideosOperation({ operation: op });
  }
  const video = op.response?.generatedVideos?.[0]?.video;
  if (!video) return null;
  const tmp = path.join(os.tmpdir(), `mg-veo-${item.id}.mp4`);
  await c.files.download({ file: video, downloadPath: tmp });
  const buf = await fs.readFile(tmp);
  await fs.unlink(tmp).catch(() => {});
  const p = `safety/${date}/${item.id}.mp4`;
  await uploadBuffer(p, buf, 'video/mp4');
  return { kind: 'veo', itemId: item.id, title: item.title, path: p, aiGenerated: true };
}

let running = null;
export const isRunning = () => Boolean(running);

/** Generates and stores a new version for `date`. Single-flight: concurrent callers share one run. */
export function generate(date = istDay()) {
  if (running) return running;
  running = (async () => {
    const c = ai();
    if (!c) throw Object.assign(new Error('FEED_NOT_CONFIGURED'), { code: 'FEED_NOT_CONFIGURED' });
    const ctx = await personalisation(date);
    const s1 = await withTimeout(c.models.generateContent({ model: env.GEMINI_MODEL, contents: [{ role: 'user', parts: [{ text: STEP1_PROMPT(ctx) }] }], config: { tools: [{ googleSearch: {} }] } }), 60_000, 'grounded search');
    const cand = s1?.candidates?.[0];
    const text = typeof s1?.text === 'string' ? s1.text : (cand?.content?.parts ?? []).map((p) => p.text ?? '').join('');
    const { text: annotated, sources } = annotate(text, cand?.groundingMetadata);
    if (!sources.length) throw Object.assign(new Error('no grounding sources returned'), { code: 'FEED_UNGROUNDED' });
    const s2 = await withTimeout(c.models.generateContent({ model: env.GEMINI_MODEL, contents: [{ role: 'user', parts: [{ text: STEP2_PROMPT(annotated) }] }], config: { responseMimeType: 'application/json', responseSchema: RESPONSE_SCHEMA } }), 40_000, 'structuring');
    let parsed;
    try {
      parsed = JSON.parse(s2?.text ?? '{}');
    } catch {
      parsed = { items: [] };
    }
    const { items, dropped } = guardItems(parsed.items, sources, allowlist(), date);
    if (dropped.length) logger.info({ dropped: dropped.length, why: [...new Set(dropped.map((d) => d.why))] }, 'safety feed: items dropped by the source guard');
    let videos = env.SAFETY_VIDEO_MODE === 'off' ? [] : storyboards(items);
    if (env.SAFETY_VIDEO_MODE === 'veo') {
      const top = items.find((i) => i.kind === 'REACT');
      const clip = top ? await veoClip(date, top).catch((err) => (logger.warn({ err: err.message }, 'veo clip failed'), null)) : null;
      if (clip) videos = [clip, ...videos];
    }
    const prev = await latest(date);
    const doc = { date, version: (prev?.version ?? 0) + 1, items, videos, generatedAt: new Date(), model: env.GEMINI_MODEL, sourcesSeen: sources.length, dropped: dropped.length, videoMode: env.SAFETY_VIDEO_MODE };
    await col().insertOne(doc);
    return doc;
  })().finally(() => {
    running = null;
  });
  return running;
}
