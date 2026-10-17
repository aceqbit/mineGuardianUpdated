import test from 'node:test';
import assert from 'node:assert/strict';
import { annotate, domainAllowed, domainOf, guardItems, istDay, RESPONSE_SCHEMA, storyboards, contextLines } from '../src/modules/safety-feed/feed.logic.js';

const ALLOW = ['dgms.gov.in', 'ilo.org', 'osha.gov', 'msha.gov', 'hse.gov.uk'];
const grounding = {
  groundingChunks: [
    { web: { uri: 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/AAA', title: 'dgms.gov.in' } },
    { web: { uri: 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/BBB', title: 'randomblog.example' } },
    { web: { uri: 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/CCC', title: 'thehindu.com' } },
  ],
  groundingSupports: [
    { segment: { startIndex: 0, endIndex: 22 }, groundingChunkIndices: [0] },
    { segment: { startIndex: 23, endIndex: 40 }, groundingChunkIndices: [1, 2] },
  ],
};

test('annotate: [S#] markers after each grounded segment; domains from chunk titles', () => {
  const { text, sources } = annotate('Wear the self-rescuer. Leave via intake.', grounding);
  assert.equal(text, 'Wear the self-rescuer. [S1] Leave via intake. [S2][S3]');
  assert.deepEqual(sources.map((s) => [s.id, s.domain]), [['S1', 'dgms.gov.in'], ['S2', 'randomblog.example'], ['S3', 'thehindu.com']]);
});

test('annotate handles multibyte text (Gemini offsets are UTF-8 bytes)', () => {
  const { text } = annotate('Gas — leave now. Next', { groundingChunks: [{ web: { title: 'osha.gov' } }], groundingSupports: [{ segment: { endIndex: Buffer.byteLength('Gas — leave now.') }, groundingChunkIndices: [0] }] });
  assert.equal(text, 'Gas — leave now. [S1] Next');
});

test('domain helpers', () => {
  assert.equal(domainOf('https://www.dgms.gov.in/x'), 'dgms.gov.in');
  assert.equal(domainOf('osha.gov'), 'osha.gov');
  assert.ok(domainAllowed('www2.osha.gov', ['osha.gov']));
  assert.ok(!domainAllowed('osha.gov.evil.com', ['osha.gov']));
  assert.ok(!domainAllowed('', ['osha.gov']));
});

const good = { kind: 'REACT', title: 'If you smell gas', body: 'Stop work, warn others and move to fresh intake air at once.', steps: ['Put on the self-rescuer', 'Walk to intake air'], hazard_category: 'GAS_LEAK', source_ids: ['S1'] };
const { sources } = annotate('x', grounding);

test('source guard keeps a grounded item from an allowed domain', () => {
  const { items, dropped } = guardItems([good], sources, ALLOW, '2026-10-17');
  assert.equal(dropped.length, 0);
  assert.equal(items[0].kind, 'REACT');
  assert.equal(items[0].hazardCategory, 'GAS_LEAK');
  assert.deepEqual(items[0].sources.map((s) => s.domain), ['dgms.gov.in']);
  assert.match(items[0].id, /^[0-9a-f]{16}$/);
});

test('source guard drops ungrounded ids, non-allowlisted domains, missing sources, invalid shapes and regulation numbers', () => {
  const bad = [
    { ...good, title: 'Invented citation', source_ids: ['S9'] },
    { ...good, title: 'Blog advice here', source_ids: ['S2'] },
    { ...good, title: 'No sources at all', source_ids: [] },
    { ...good, title: 'x', body: 'short' },
    { ...good, title: 'Rule with a number', body: 'As per Regulation 123 of the mine rules everyone must carry a lamp at all times.' },
    { ...good, title: 'Mixed sources here', source_ids: ['S1', 'S2'] },
  ];
  const { items, dropped } = guardItems(bad, sources, ALLOW, '2026-10-17');
  assert.equal(items.length, 0);
  assert.equal(dropped.length, 6);
  assert.ok(dropped.some((d) => /grounding metadata/.test(d.why)));
  assert.ok(dropped.some((d) => /not allowed/.test(d.why)));
  assert.ok(dropped.some((d) => /regulation/.test(d.why)));
});

test('a LESSON may cite a news site; other kinds may not', () => {
  const news = { ...good, kind: 'LESSON', title: 'Lesson from a roof fall', source_ids: ['S3'] };
  assert.equal(guardItems([news], sources, ALLOW, 'd').items.length, 1);
  assert.equal(guardItems([{ ...news, kind: 'RULE' }], sources, ALLOW, 'd').items.length, 0);
});

test('storyboards for REACT / PREVENT, schema uses only allowed keywords, IST day, context lines', () => {
  const { items } = guardItems([good, { ...good, kind: 'RULE', title: 'Rule of the day' }], sources, ALLOW, 'd');
  const sb = storyboards(items);
  assert.equal(sb.length, 1);
  assert.deepEqual(sb[0].frames, [good.body, ...good.steps]);
  const keys = new Set();
  JSON.stringify(RESPONSE_SCHEMA, (k, v) => (keys.add(k), v));
  for (const k of ['oneOf', '$ref', 'anyOf']) assert.ok(!keys.has(k), k);
  assert.equal(istDay(new Date('2026-10-16T20:00:00Z')), '2026-10-17');
  const ctx = contextLines({ date: '2026-10-17', zones: [{ code: 'Z-B', requiredPpe: ['HELMET', 'SAFETY_BOOTS'] }], hazardCategories: ['ROOF_FALL'], missedPpe: ['GLOVES'] });
  assert.match(ctx.join(' '), /Zone Z-B requires: helmet, safety boots\..*roof fall.*gloves/);
});
