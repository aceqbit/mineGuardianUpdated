// Profile manager data (CLAUDE.md section 23.2). Phase 1 data through its models, Phase 2 / add-on data from raw
// collections so a missing module only leaves a section empty (`null`), never invented.
import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { signedUrl } from '../../core/storage.js';
import { maskPhone } from '../../core/logger.js';
import { maskEmail } from '../../core/mailer.js';
import { CheckIn } from '../../models/CheckIn.js';
import { Hazard } from '../../models/Hazard.js';
import { SosEvent } from '../../models/SosEvent.js';
import { User } from '../../models/User.js';
import { Zone } from '../../models/Zone.js';
import { accessLevel, competitionRank, complianceCalendar, expiringCertifications, istDay, listScope, trimCard, trimProfile } from './profiles.logic.js';

const DAY_MS = 86_400_000;
const raw = (name) => mongoose.connection.collection(name);
const safe = async (fn, fallback = null) => {
  try {
    return await fn();
  } catch {
    return fallback;
  }
};
const iso = (d) => (d ? new Date(d).toISOString() : null);

async function zonesById() {
  const zones = await Zone.find().select('code name requiredPpe');
  return new Map(zones.map((z) => [String(z._id), z]));
}

/** Latest score snapshot per user (raw `score_snapshots`). */
async function latestSnapshots(userIds) {
  return safe(async () => {
    const rows = await raw('score_snapshots')
      .aggregate([{ $match: { userId: { $in: userIds } } }, { $sort: { day: -1 } }, { $group: { _id: '$userId', s: { $first: '$$ROOT' } } }])
      .toArray();
    return new Map(rows.map((r) => [String(r._id), r.s]));
  }, new Map());
}

async function presenceMap(userIds) {
  return safe(async () => {
    const rows = await raw('live_positions').find({ userId: { $in: userIds.map(String) } }).toArray();
    return new Map(rows.map((r) => [String(r.userId), r]));
  }, new Map());
}

/** LIVE/STALE/OFFLINE from the last fix time (tracking module thresholds). */
export function presenceOf(pos, now = Date.now(), staleSec = 30, offlineSec = 120) {
  if (!pos?.ts) return 'OFFLINE';
  const age = (now - new Date(pos.ts).getTime()) / 1000;
  if (age < staleSec) return 'LIVE';
  return age < offlineSec ? 'STALE' : 'OFFLINE';
}

async function latestPhotos(userIds) {
  const rows = await CheckIn.aggregate([
    { $match: { workerId: { $in: userIds } } },
    { $sort: { createdAt: -1 } },
    { $group: { _id: '$workerId', c: { $first: '$$ROOT' } } },
  ]);
  const out = new Map();
  await Promise.all(rows.map(async (r) => out.set(String(r._id), { path: r.c.storagePath, url: await signedUrl(r.c.storagePath).catch(() => null), checkInId: String(r.c._id), status: r.c.status, at: iso(r.c.capturedAt || r.c.receivedAt || r.c.createdAt) })));
  return out;
}

function identity(u, zone, viewer) {
  const admin = viewer.role === 'admin';
  return {
    id: String(u._id), fullName: u.fullName, employeeId: u.employeeId, role: u.role, status: u.status, shift: u.shift ?? null,
    zone: zone ? { id: String(zone._id), code: zone.code, name: zone.name } : null,
    email: u.email ? (admin ? u.email : maskEmail(u.email)) : null,
    phoneMasked: u.phone?.e164 ? maskPhone(u.phone.e164) : null,
    hasPhone: Boolean(u.phone?.e164),
    phoneE164: admin ? (u.phone?.e164 ?? null) : undefined,
    joinedAt: iso(u.dateOfJoining || u.createdAt),
  };
}

/** GET /api/profiles: cards for the viewer's scope. */
export async function listProfiles(viewer, { role, zoneId, q, limit = 100, cursor = 0 }) {
  if (viewer.role === 'supervisor' && zoneId && String(zoneId) !== String(viewer.zoneId)) throw new AppError(403, 'FORBIDDEN_SCOPE', 'You can only view your own zone');
  const filter = listScope(viewer, { role, zoneId });
  if (q) {
    const rx = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
    filter.$and = [...(filter.$and ?? []), { $or: [{ fullName: rx }, { employeeId: rx }] }];
  }
  const [users, total, zones] = await Promise.all([
    User.find(filter).sort({ role: 1, fullName: 1 }).skip(cursor).limit(limit),
    User.countDocuments(filter),
    zonesById(),
  ]);
  const ids = users.map((u) => u._id);
  const dayStart = new Date(`${istDay(new Date())}T00:00:00+05:30`);
  const [snaps, photos, pres, todays] = await Promise.all([
    latestSnapshots(ids),
    latestPhotos(ids),
    presenceMap(ids),
    CheckIn.find({ workerId: { $in: ids }, createdAt: { $gte: dayStart } }).sort({ createdAt: -1 }),
  ]);
  const zoneRows = await safe(async () => raw('score_snapshots').aggregate([{ $sort: { day: -1 } }, { $group: { _id: '$userId', s: { $first: '$$ROOT' } } }]).toArray(), []);
  const todayBy = new Map();
  for (const c of todays) if (!todayBy.has(String(c.workerId))) todayBy.set(String(c.workerId), c);
  const reviews = await safe(async () => new Map((await raw('compliance_reviews').find({ checkInId: { $in: todays.map((c) => c._id) } }).toArray()).map((r) => [String(r.checkInId), r])), new Map());

  const items = users.map((u) => {
    const level = accessLevel(viewer, u);
    const s = snaps.get(String(u._id));
    const zone = zones.get(String(u.zoneId));
    const sameZone = zoneRows.filter((r) => String(r.s.zoneId) === String(u.zoneId)).map((r) => ({ userId: r._id, score: r.s.score, streak: r.s.streak, xp: r.s.xp }));
    const ci = todayBy.get(String(u._id));
    const rv = ci ? reviews.get(String(ci._id)) : null;
    const pos = pres.get(String(u._id));
    return trimCard({
      id: String(u._id), fullName: u.fullName, employeeId: u.employeeId, role: u.role, status: u.status, shift: u.shift ?? null,
      zone: zone ? { id: String(zone._id), code: zone.code, name: zone.name } : null,
      designation: u.designation ?? null,
      photo: photos.get(String(u._id)) ?? null,
      today: u.role === 'miner' ? { status: ci ? ci.status : 'NOT_CHECKED_IN', verdict: rv?.decision?.finalVerdict ?? rv?.ai?.overallVerdict ?? null } : null,
      score: s ? { score: s.score, streak: s.streak ?? 0, xp: s.xp ?? 0, badges: (s.badges ?? []).length, rank: competitionRank(sameZone, u._id)?.rank ?? null } : null,
      riskBand: s?.riskBand ?? null,
      presence: pos ? presenceOf(pos) : null,
    }, level);
  });
  const next = cursor + users.length < total ? cursor + users.length : null;
  return { items: items.filter(Boolean), total, nextCursor: next };
}

/** GET /api/profiles/:userId: the full profile, trimmed by the viewer's access level. */
export async function getProfile(viewer, userId, now = new Date()) {
  const u = await User.findById(userId);
  if (!u) throw new AppError(404, 'NOT_FOUND', 'User not found');
  const level = accessLevel(viewer, u);
  if (!level) throw new AppError(403, 'FORBIDDEN_SCOPE', 'This profile is outside your scope');
  const id = u._id;
  const zone = u.zoneId ? await Zone.findById(u.zoneId) : null;
  const since30 = new Date(now.getTime() - 30 * DAY_MS);

  const [checkins, snapRows, photos, pres, hazards, hazardCounts, sos, rewards, crisis] = await Promise.all([
    u.role === 'miner' ? CheckIn.find({ workerId: id, createdAt: { $gte: since30 } }).sort({ createdAt: -1 }) : [],
    safe(() => raw('score_snapshots').aggregate([{ $match: u.zoneId ? { zoneId: u.zoneId } : { userId: id } }, { $sort: { day: -1 } }, { $group: { _id: '$userId', s: { $first: '$$ROOT' } } }]).toArray(), []),
    latestPhotos([id]),
    presenceMap([id]),
    Hazard.find({ reporterId: id }).sort({ createdAt: -1 }).limit(5),
    Hazard.aggregate([{ $match: { reporterId: id } }, { $group: { _id: '$status', n: { $sum: 1 } } }]),
    SosEvent.find({ workerId: id }).sort({ createdAt: -1 }).limit(5),
    safe(() => raw('rewards').find({ userId: id }).sort({ month: -1 }).limit(12).toArray(), []),
    safe(() => raw('crises').findOne({ status: 'ACTIVE', ...(u.zoneId ? { zoneIds: u.zoneId } : {}) }), null),
  ]);
  const sosCount = await SosEvent.countDocuments({ workerId: id });
  const reviews = await safe(async () => new Map((await raw('compliance_reviews').find({ checkInId: { $in: checkins.map((c) => c._id) } }).toArray()).map((r) => [String(r.checkInId), r])), new Map());
  const mine = snapRows.find((r) => String(r._id) === String(id))?.s;
  const rank = mine ? competitionRank(snapRows.map((r) => ({ userId: r._id, score: r.s.score, streak: r.s.streak, xp: r.s.xp })), id) : null;
  const latest = checkins[0];
  const latestReview = latest ? reviews.get(String(latest._id)) : null;
  const pos = pres.get(String(id));

  let supervisorStats = null;
  if (u.role === 'supervisor') {
    supervisorStats = await safe(async () => {
      const col = raw('compliance_reviews');
      const decided = await col.find({ 'decision.decidedBy': id, 'decision.decidedAt': { $gte: since30 } }).toArray();
      const onTime = decided.filter((r) => r.sla?.dueAt && new Date(r.decision.decidedAt) <= new Date(r.sla.dueAt)).length;
      const breaches = await col.countDocuments({ zoneId: u.zoneId, 'sla.breached': true, 'sla.compensated': { $ne: true }, 'sla.breachedAt': { $gte: since30 } });
      const pending = await col.countDocuments({ zoneId: u.zoneId, status: 'PENDING_REVIEW' });
      const total = decided.length + breaches;
      const reliability = total ? Math.max(0, Math.min(100, Math.round((100 * onTime) / total - 5 * breaches))) : null;
      const team = await User.countDocuments({ role: 'miner', zoneId: u.zoneId, status: 'active' });
      return { decided30d: decided.length, onTime, breaches, pending, reliability, teamSize: team };
    }, null);
  }

  const accounted = crisis ? (crisis.accounted ?? []).find((a) => String(a.workerId) === String(id))?.status ?? 'UNKNOWN' : null;
  const profile = {
    ...identity(u, zone, viewer),
    level,
    designation: u.designation ?? null,
    experienceYears: u.experienceYears ?? null,
    bloodGroup: u.bloodGroup ?? null,
    dob: iso(u.dob),
    certifications: (u.certifications ?? []).map((c) => ({ name: c.name, issuedAt: iso(c.issuedAt), expiresAt: iso(c.expiresAt) })),
    certificationsExpiring: expiringCertifications((u.certifications ?? []).map((c) => ({ name: c.name, expiresAt: c.expiresAt })), now).map((c) => ({ name: c.name, expiresAt: iso(c.expiresAt), expired: c.expired })),
    medicalNotes: u.medicalNotes ?? null,
    photo: photos.get(String(id)) ?? null,
    requiredPpe: zone?.requiredPpe ?? [],
    today: u.role === 'miner' ? {
      status: latest && istDay(latest.createdAt) === istDay(now) ? latest.status : 'NOT_CHECKED_IN',
      verdict: latest && istDay(latest.createdAt) === istDay(now) ? (latestReview?.decision?.finalVerdict ?? latestReview?.ai?.overallVerdict ?? null) : null,
      checkInId: latest && istDay(latest.createdAt) === istDay(now) ? String(latest._id) : null,
    } : null,
    calendar: u.role === 'miner' ? complianceCalendar(checkins, reviews, now) : null,
    score: mine ? { score: mine.score, streak: mine.streak ?? 0, xp: mine.xp ?? 0, badges: mine.badges ?? [], riskBand: mine.riskBand ?? null, rank: rank?.rank ?? null, rankOf: rank?.of ?? null, components: mine.components ?? null, day: mine.day } : null,
    rewards: rewards.map((r) => ({ month: r.month, key: r.key, title: r.title, rank: r.rank, stars: r.stars, demo: r.demo !== false })),
    hazards: {
      counts: Object.fromEntries(hazardCounts.map((h) => [h._id, h.n])),
      recent: hazards.map((h) => ({ id: String(h._id), category: h.category, severity: h.ai?.severity ?? null, status: h.status, createdAt: iso(h.createdAt) })),
    },
    sos: { count: sosCount, recent: sos.map((s) => ({ id: String(s._id), status: s.status, createdAt: iso(s.createdAt) })) },
    supervisorStats,
    crisis: crisis ? { crisisId: String(crisis._id), accounted } : null,
    presence: pos ? { presence: presenceOf(pos), lat: pos.lat, lng: pos.lng, accuracyM: pos.accuracyM, source: pos.source ?? 'GPS', tunnelId: pos.tunnelId ?? null, ts: iso(pos.ts) } : null,
  };
  return trimProfile(profile, level);
}

/** PATCH /api/profiles/:userId. Admin: profile block, status, shift, phone, miner zone. Self: designation only. */
export async function patchProfile(viewer, userId, body) {
  const u = await User.findById(userId);
  if (!u) throw new AppError(404, 'NOT_FOUND', 'User not found');
  const self = String(viewer._id) === String(u._id);
  const isAdmin = viewer.role === 'admin';
  const keys = Object.keys(body);
  if (!isAdmin) {
    if (!self) throw new AppError(403, 'FORBIDDEN_SCOPE', 'Only an admin can edit another profile');
    const bad = keys.filter((k) => k !== 'designation');
    if (bad.length) throw new AppError(403, 'FORBIDDEN_FIELD', 'You can only change your designation', { fields: bad });
  }
  if (body.zoneId !== undefined && u.role !== 'miner') throw new AppError(400, 'USE_ZONE_SUPERVISORS', 'Move supervisors with PUT /api/zones/:id/supervisors');
  if (body.zoneId && !(await Zone.exists({ _id: body.zoneId }))) throw new AppError(400, 'VALIDATION_ERROR', 'Unknown zone', [{ path: 'zoneId', message: 'Unknown zone' }]);
  if (body.status === 'inactive' && self) throw new AppError(400, 'VALIDATION_ERROR', 'You cannot deactivate yourself', [{ path: 'status', message: 'self' }]);

  const prevZone = u.zoneId ? String(u.zoneId) : null;
  for (const k of ['designation', 'bloodGroup', 'experienceYears', 'medicalNotes', 'status', 'shift', 'zoneId']) if (body[k] !== undefined) u[k] = body[k];
  if (body.dateOfJoining !== undefined) u.dateOfJoining = body.dateOfJoining ? new Date(body.dateOfJoining) : undefined;
  if (body.certifications !== undefined) u.certifications = body.certifications;
  if (body.phoneE164 !== undefined) u.phone = body.phoneE164 ? { e164: body.phoneE164 } : undefined;
  await u.save();
  const changed = [...new Set(keys.map((k) => (['status', 'shift', 'zoneId', 'designation', 'phoneE164'].includes(k) ? 'identity' : 'details')))];
  return { user: u, changed, prevZone, fields: keys };
}
