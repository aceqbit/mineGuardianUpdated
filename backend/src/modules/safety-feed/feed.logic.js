// Pure rules of the daily safety feed (CLAUDE.md section 23.6). Unit-tested; no I/O.
import crypto from 'node:crypto';
import { z } from 'zod';
import { HAZARD_CATEGORY, SAFETY_ITEM_KIND } from '../../contracts/enums.js';

/** News sites a LESSON (recent incident) may cite in addition to the safety allowlist. */
export const NEWS_DOMAINS = Object.freeze(['thehindu.com', 'indianexpress.com', 'timesofindia.indiatimes.com', 'hindustantimes.com', 'ndtv.com', 'reuters.com', 'bbc.com', 'bbc.co.uk', 'downtoearth.org.in', 'business-standard.com', 'livemint.com', 'pib.gov.in']);

/** IST calendar day. */
export const istDay = (d = new Date()) => new Date(new Date(d).getTime() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);

export const domainOf = (s) => {
  const raw = String(s ?? '').trim().toLowerCase();
  if (!raw) return '';
  try {
    return new URL(raw.includes('://') ? raw : `https://${raw}`).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
};

/** a.b.gov.in matches gov.in-style entries and the exact domain. */
export const domainAllowed = (domain, list) => Boolean(domain) && list.some((d) => domain === d || domain.endsWith(`.${d}`));

/**
 * Grounding metadata -> sources [{id:'S1', domain, title, url}] and the step-1 text with [S#] markers after each
 * supported segment. Gemini's chunk URIs are redirect links; the chunk title carries the real domain.
 */
export function annotate(text, grounding) {
  const chunks = grounding?.groundingChunks ?? [];
  const sources = chunks.map((c, i) => {
    const title = c?.web?.title ?? '';
    const url = c?.web?.uri ?? '';
    const d = domainOf(title) && domainOf(title).includes('.') ? domainOf(title) : domainOf(url);
    return { id: `S${i + 1}`, domain: d, title, url };
  });
  const supports = [...(grounding?.groundingSupports ?? [])]
    .filter((s) => Number.isInteger(s?.segment?.endIndex) && s.groundingChunkIndices?.length)
    .sort((a, b) => b.segment.endIndex - a.segment.endIndex);
  // Gemini indexes are UTF-8 byte offsets.
  let buf = Buffer.from(String(text ?? ''), 'utf8');
  for (const s of supports) {
    const marks = Buffer.from(` ${s.groundingChunkIndices.map((i) => `[S${i + 1}]`).join('')}`, 'utf8');
    const at = Math.min(s.segment.endIndex, buf.length);
    buf = Buffer.concat([buf.subarray(0, at), marks, buf.subarray(at)]);
  }
  return { text: buf.toString('utf8'), sources };
}

const REGULATION_RX = /\b(regulation|reg\.|section|sec\.|rule|clause|circular|notification)\s*(no\.?\s*)?\d+/i;

export const itemSchema = z.object({
  kind: z.enum(SAFETY_ITEM_KIND),
  title: z.string().trim().min(4).max(80),
  body: z.string().trim().min(20).max(400),
  steps: z.array(z.string().trim().min(2).max(140)).max(6).default([]),
  hazard_category: z.enum(HAZARD_CATEGORY).nullish(),
  source_ids: z.array(z.string().regex(/^S\d+$/)).min(1),
});

/** Gemini response schema for step 2 (only type/properties/required/enum/items, per CLAUDE.md section 10). */
export const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: [...SAFETY_ITEM_KIND] },
          title: { type: 'string' },
          body: { type: 'string' },
          steps: { type: 'array', items: { type: 'string' } },
          hazard_category: { type: 'string', enum: [...HAZARD_CATEGORY] },
          source_ids: { type: 'array', items: { type: 'string' } },
        },
        required: ['kind', 'title', 'body', 'steps', 'source_ids'],
      },
    },
  },
  required: ['items'],
};

/**
 * Source guard. Keeps an item only when it validates, cites at least one source, every cited id is a real grounding
 * chunk on an allowed domain (LESSON may also cite NEWS_DOMAINS), and it quotes no regulation / section / rule
 * number (we cannot open the source pages to check one). Returns { items, dropped:[{title, why}] }.
 */
export function guardItems(rawItems, sources, allowlist, date) {
  const byId = new Map(sources.map((s) => [s.id, s]));
  const items = [];
  const dropped = [];
  for (const r of Array.isArray(rawItems) ? rawItems : []) {
    const p = itemSchema.safeParse(r);
    if (!p.success) {
      dropped.push({ title: String(r?.title ?? '').slice(0, 80), why: 'invalid shape' });
      continue;
    }
    const it = p.data;
    const cited = [...new Set(it.source_ids)].map((id) => byId.get(id));
    const allowed = it.kind === 'LESSON' ? [...allowlist, ...NEWS_DOMAINS] : allowlist;
    if (cited.some((s) => !s)) {
      dropped.push({ title: it.title, why: 'cites a source that is not in the grounding metadata' });
      continue;
    }
    if (cited.some((s) => !domainAllowed(s.domain, allowed))) {
      dropped.push({ title: it.title, why: `source domain not allowed: ${cited.map((s) => s.domain).join(', ')}` });
      continue;
    }
    const text = [it.title, it.body, ...it.steps].join(' ');
    if (REGULATION_RX.test(text)) {
      dropped.push({ title: it.title, why: 'quotes a regulation number that cannot be verified' });
      continue;
    }
    items.push({
      id: crypto.createHash('sha1').update(`${date}|${it.kind}|${it.title}`).digest('hex').slice(0, 16),
      kind: it.kind,
      title: it.title,
      body: it.body,
      steps: it.steps,
      hazardCategory: it.hazard_category ?? null,
      sources: cited.map((s) => ({ domain: s.domain, title: s.title, url: s.url })),
    });
  }
  return { items, dropped };
}

/** Storyboard explainers for REACT / PREVENT items (rendered and narrated on the phone). */
export function storyboards(items) {
  return items.filter((i) => i.kind === 'REACT' || i.kind === 'PREVENT').slice(0, 6).map((i) => ({ kind: 'storyboard', itemId: i.id, title: i.title, frames: [i.body, ...i.steps].slice(0, 7) }));
}

/** The facts that personalise today's prompt (zones' PPE, open hazards, recent misses). */
export function contextLines({ date, zones = [], hazardCategories = [], missedPpe = [] }) {
  const lines = [`Today is ${date} (India Standard Time). The mine is an underground coal mine in India regulated by DGMS.`];
  for (const z of zones) lines.push(`Zone ${z.code} requires: ${(z.requiredPpe ?? []).map((k) => k.replace(/_/g, ' ').toLowerCase()).join(', ')}.`);
  if (hazardCategories.length) lines.push(`Open hazards right now: ${hazardCategories.map((c) => c.replace(/_/g, ' ').toLowerCase()).join(', ')}.`);
  if (missedPpe.length) lines.push(`PPE most often missing in the last 7 days: ${missedPpe.map((c) => c.replace(/_/g, ' ').toLowerCase()).join(', ')}.`);
  return lines;
}

export const STEP1_PROMPT = (ctx) => `${ctx.join('\n')}

Search the web for current, authoritative mine-safety guidance (DGMS, ILO, MSHA, OSHA, HSE) and, for one item, a real mining incident from the last 12 months.
Write today's safety briefing for underground coal miners as short plain paragraphs, each starting with its label:
RULE: one rule of the day relevant to the PPE or hazards above.
PREVENT: two ways to prevent the most likely accidents above.
REACT: how to react to a gas leak, a roof fall, fire or smoke, flooding, an electrical accident and an injured person (one paragraph each, concrete steps).
LESSON: one recent incident and what it teaches (only if you find a real one).
Use only what the sources say. Do not quote regulation, section or rule numbers.`;

export const STEP2_PROMPT = (annotated) => `Turn this grounded briefing into JSON items. Each item: kind (RULE, PREVENT, REACT, LESSON), title (max 80 chars), body (max 400 chars), steps (max 6 short imperative steps, may be empty), hazard_category when it is about one hazard, and source_ids: the [S#] markers that appear in the sentences you used (copy them exactly, at least one). Do not add facts that are not in the text.

BRIEFING
${annotated}`;
