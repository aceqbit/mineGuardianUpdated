import test from 'node:test';
import assert from 'node:assert/strict';
import { accessLevel, competitionRank, complianceCalendar, expiringCertifications, listScope, roomsFor, trimCard, trimProfile } from '../src/modules/profiles/profiles.logic.js';
import { presenceOf } from '../src/modules/profiles/profiles.service.js';
import { patchSchema } from '../src/modules/profiles/index.js';

const ZA = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const ZB = 'bbbbbbbbbbbbbbbbbbbbbbbb';
const u = (id, role, zoneId) => ({ _id: id, role, zoneId });
const admin = u('a1', 'admin');
const supA = u('s1', 'supervisor', ZA);
const minerA1 = u('m1', 'miner', ZA);
const minerA2 = u('m2', 'miner', ZA);
const minerB = u('m3', 'miner', ZB);

test('access matrix: admin full, supervisor own zone only, miner self + crew', () => {
  assert.equal(accessLevel(admin, minerB), 'full');
  assert.equal(accessLevel(supA, minerA1), 'full');
  assert.equal(accessLevel(supA, supA), 'full');
  assert.equal(accessLevel(supA, minerB), null, 'Z-A supervisor must not read a Z-B miner');
  assert.equal(accessLevel(supA, admin), null);
  assert.equal(accessLevel(minerA1, minerA1), 'self');
  assert.equal(accessLevel(minerA1, minerA2), 'crew');
  assert.equal(accessLevel(minerA1, supA), 'crew');
  assert.equal(accessLevel(minerA1, minerB), null);
  assert.equal(accessLevel(minerA1, admin), null);
});

test('list scope never leaks another zone', () => {
  assert.deepEqual(listScope(supA, { zoneId: ZB }), { $or: [{ role: 'miner', zoneId: ZA }, { _id: 's1' }] });
  assert.deepEqual(listScope(minerA1, {}), { zoneId: ZA, role: { $in: ['miner', 'supervisor'] }, status: 'active' });
  assert.deepEqual(listScope(admin, { role: 'miner', zoneId: ZB }), { role: 'miner', zoneId: ZB });
});

const full = {
  id: 'm2', fullName: 'Ravi', employeeId: 'MIN-0102', role: 'miner', zone: { code: 'Z-A' }, shift: 'A', status: 'active',
  email: 'r***@x.com', phoneMasked: '+91******0101', medicalNotes: 'asthma', calendar: [{ day: '2026-10-01', verdict: 'NON_COMPLIANT' }],
  photo: { url: 'u' }, presence: { presence: 'LIVE', lat: 1, lng: 2 },
  score: { score: 640, streak: 3, xp: 120, badges: [], rank: 2, riskBand: 'AMBER', components: { C: 1 } },
};

test('crew view: public card only, never risk band, phone, email, violations or position', () => {
  const c = trimProfile(full, 'crew');
  assert.equal(c.fullName, 'Ravi');
  assert.equal(c.score.streak, 3);
  assert.equal(c.score.rank, 2);
  for (const k of ['email', 'phoneMasked', 'medicalNotes', 'calendar']) assert.equal(c[k], undefined, k);
  assert.equal(c.score.riskBand, undefined);
  assert.equal(c.score.score, undefined);
  assert.equal(c.score.components, undefined);
  assert.deepEqual(c.presence, { presence: 'LIVE' });
});

test('self view hides only the risk band', () => {
  const s = trimProfile(full, 'self');
  assert.equal(s.score.riskBand, undefined);
  assert.equal(s.score.score, 640);
  assert.equal(s.medicalNotes, 'asthma');
  assert.equal(full.score.riskBand, 'AMBER', 'input untouched');
});

test('cards: risk band only for full access', () => {
  const card = { id: 'm2', riskBand: 'RED', email: 'x', score: { score: 1 } };
  assert.equal(trimCard(card, 'full').riskBand, 'RED');
  assert.equal(trimCard(card, 'self').riskBand, undefined);
  const crew = trimCard(card, 'crew');
  assert.equal(crew.riskBand, undefined);
  assert.equal(crew.score, undefined);
  assert.equal(trimCard(card, null), null);
});

test('calendar: 30 IST days, latest check-in of the day wins, human verdict beats AI', () => {
  const now = new Date('2026-10-17T06:00:00Z'); // 11:30 IST
  const checkins = [
    { _id: 'c1', createdAt: new Date('2026-10-17T01:00:00Z') },
    { _id: 'c2', createdAt: new Date('2026-10-17T04:00:00Z') },
    { _id: 'c3', createdAt: new Date('2026-10-15T20:00:00Z') }, // 01:30 IST on the 16th
  ];
  const reviews = new Map([
    ['c1', { ai: { overallVerdict: 'NON_COMPLIANT' } }],
    ['c2', { ai: { overallVerdict: 'NEEDS_MANUAL_REVIEW' }, status: 'DECIDED', decision: { finalVerdict: 'COMPLIANT' } }],
    ['c3', { ai: { overallVerdict: 'NON_COMPLIANT' } }],
  ]);
  const cal = complianceCalendar(checkins, reviews, now);
  assert.equal(cal.length, 30);
  assert.deepEqual(cal.at(-1), { day: '2026-10-17', verdict: 'COMPLIANT', decided: true, checkInId: 'c2' });
  assert.equal(cal.at(-2).day, '2026-10-16');
  assert.equal(cal.at(-2).verdict, 'NON_COMPLIANT');
  assert.equal(cal.at(-3).verdict, null);
});

test('competition rank: ties share a rank, next rank skips', () => {
  const rows = [
    { userId: 'a', score: 900, streak: 5, xp: 10 },
    { userId: 'b', score: 800, streak: 1, xp: 1 },
    { userId: 'c', score: 800, streak: 1, xp: 1 },
    { userId: 'd', score: 700, streak: 0, xp: 0 },
  ];
  assert.deepEqual(competitionRank(rows, 'c'), { rank: 2, of: 4 });
  assert.deepEqual(competitionRank(rows, 'd'), { rank: 4, of: 4 });
  assert.equal(competitionRank(rows, 'zz'), null);
});

test('certifications expiring within 30 days are flagged', () => {
  const now = new Date('2026-10-17T00:00:00Z');
  const out = expiringCertifications([
    { name: 'Gas testing', expiresAt: new Date('2026-11-01') },
    { name: 'First aid', expiresAt: new Date('2027-06-01') },
    { name: 'Blasting', expiresAt: new Date('2026-09-01') },
  ], now);
  assert.deepEqual(out.map((c) => [c.name, c.expired]), [['Gas testing', false], ['Blasting', true]]);
});

test('rooms: crew-visible changes reach the zone, private ones do not', () => {
  assert.deepEqual(roomsFor(minerA1, ['hazards']), ['user:m1', 'role:admin', `zone:${ZA}:supervisors`]);
  assert.ok(roomsFor(minerA1, ['photo']).includes(`zone:${ZA}`));
  assert.deepEqual(roomsFor(admin, ['identity']), ['user:a1', 'role:admin']);
});

test('presence thresholds: LIVE < 30 s, STALE < 120 s, then OFFLINE', () => {
  const now = Date.parse('2026-10-17T10:00:00Z');
  assert.equal(presenceOf({ ts: '2026-10-17T09:59:50Z' }, now), 'LIVE');
  assert.equal(presenceOf({ ts: '2026-10-17T09:59:00Z' }, now), 'STALE');
  assert.equal(presenceOf({ ts: '2026-10-17T09:50:00Z' }, now), 'OFFLINE');
  assert.equal(presenceOf(null, now), 'OFFLINE');
});

test('PATCH schema: strict, validates phone and blood group, rejects empty', () => {
  assert.ok(patchSchema.safeParse({ designation: 'Shot firer' }).success);
  assert.ok(patchSchema.safeParse({ phoneE164: '+919876500101' }).success);
  assert.ok(patchSchema.safeParse({ phoneE164: null }).success);
  assert.equal(patchSchema.safeParse({ phoneE164: '9876500101' }).success, false);
  assert.equal(patchSchema.safeParse({ bloodGroup: 'Z+' }).success, false);
  assert.equal(patchSchema.safeParse({}).success, false);
  assert.equal(patchSchema.safeParse({ role: 'admin' }).success, false, 'role cannot be changed here');
  assert.equal(patchSchema.safeParse({ certifications: [{ name: 'X' }] }).success, false);
});
