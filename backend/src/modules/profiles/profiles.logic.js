// Pure rules of the profile manager (CLAUDE.md section 23.2). No I/O here; unit-tested.

const DAY_MS = 86_400_000;

/**
 * How much of `target` the `viewer` may see.
 * 'full'  admin on anyone, supervisor on their own zone's miners and on themselves
 * 'self'  a miner on themselves (everything except the risk band)
 * 'crew'  a miner on a miner or supervisor of their own zone (public card only)
 * null    out of scope
 */
export function accessLevel(viewer, target) {
  if (!viewer || !target) return null;
  const same = String(viewer._id ?? viewer.id) === String(target._id ?? target.id);
  if (viewer.role === 'admin') return 'full';
  const sameZone = viewer.zoneId && target.zoneId && String(viewer.zoneId) === String(target.zoneId);
  if (viewer.role === 'supervisor') {
    if (same) return 'full';
    return sameZone && target.role === 'miner' ? 'full' : null;
  }
  if (viewer.role === 'miner') {
    if (same) return 'self';
    return sameZone && (target.role === 'miner' || target.role === 'supervisor') ? 'crew' : null;
  }
  return null;
}

/** List filter a viewer is allowed to run. Returns a Mongo filter for `users`. */
export function listScope(viewer, { role, zoneId } = {}) {
  if (viewer.role === 'admin') {
    const f = {};
    if (role) f.role = role;
    if (zoneId) f.zoneId = zoneId;
    return f;
  }
  const zone = viewer.zoneId;
  if (viewer.role === 'supervisor') {
    // own zone's miners, plus the supervisor themselves
    return { $or: [{ role: 'miner', zoneId: zone }, { _id: viewer._id }] };
  }
  return { zoneId: zone, role: { $in: ['miner', 'supervisor'] }, status: 'active' };
}

/** Fields each level keeps. Anything else is dropped. */
const CREW_KEYS = ['id', 'fullName', 'employeeId', 'role', 'zone', 'shift', 'status', 'photo', 'presence', 'score'];
const CREW_SCORE_KEYS = ['streak', 'xp', 'badges', 'rank'];

export function trimProfile(p, level) {
  if (!p || !level) return null;
  if (level === 'full') return p;
  if (level === 'self') {
    const out = { ...p, level: 'self' };
    if (out.score) {
      out.score = { ...out.score };
      delete out.score.riskBand;
    }
    return out;
  }
  const out = {};
  for (const k of CREW_KEYS) if (p[k] !== undefined) out[k] = p[k];
  if (p.score) out.score = Object.fromEntries(CREW_SCORE_KEYS.filter((k) => p.score[k] !== undefined).map((k) => [k, p.score[k]]));
  if (out.presence) out.presence = { presence: out.presence.presence };
  out.level = 'crew';
  return out;
}

/** Card for the list; `riskBand` only when the viewer may see it. */
export function trimCard(card, level) {
  if (!card || !level) return null;
  const out = { ...card, level };
  if (level !== 'full') delete out.riskBand;
  if (level === 'crew') {
    delete out.email;
    delete out.phoneMasked;
    delete out.score;
  }
  return out;
}

/** IST yyyy-mm-dd for a Date. */
export const istDay = (d) => new Date(new Date(d).getTime() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);

/**
 * 30-day compliance calendar, oldest first. `checkins` = [{_id, createdAt|capturedAt}], `reviews` = Map(checkInId -> review).
 * One cell per IST day: the latest check-in of that day decides; finalVerdict (human) beats the AI verdict.
 */
export function complianceCalendar(checkins, reviews, now = new Date(), days = 30) {
  const latest = new Map();
  for (const c of checkins) {
    const at = c.capturedAt || c.receivedAt || c.createdAt;
    const day = istDay(at);
    const prev = latest.get(day);
    if (!prev || new Date(at) > new Date(prev.at)) latest.set(day, { at, c });
  }
  const out = [];
  for (let i = days - 1; i >= 0; i -= 1) {
    const day = istDay(new Date(now).getTime() - i * DAY_MS);
    const hit = latest.get(day);
    if (!hit) {
      out.push({ day, verdict: null, checkInId: null });
      continue;
    }
    const r = reviews.get(String(hit.c._id));
    out.push({ day, verdict: r?.decision?.finalVerdict ?? r?.ai?.overallVerdict ?? null, decided: r?.status === 'DECIDED', checkInId: String(hit.c._id) });
  }
  return out;
}

/** Standard competition rank (score, streak, xp desc, name asc) of `userId` among the latest snapshots. */
export function competitionRank(rows, userId) {
  const sorted = [...rows].sort((a, b) => b.score - a.score || (b.streak ?? 0) - (a.streak ?? 0) || (b.xp ?? 0) - (a.xp ?? 0) || String(a.name ?? '').localeCompare(String(b.name ?? '')));
  let rank = 0;
  let prev = null;
  for (let i = 0; i < sorted.length; i += 1) {
    const r = sorted[i];
    const key = `${r.score}|${r.streak ?? 0}|${r.xp ?? 0}`;
    if (key !== prev) rank = i + 1;
    prev = key;
    if (String(r.userId) === String(userId)) return { rank, of: sorted.length };
  }
  return null;
}

/** Certifications that expire within `withinDays` (or already expired). */
export function expiringCertifications(certs = [], now = new Date(), withinDays = 30) {
  const limit = new Date(now).getTime() + withinDays * DAY_MS;
  return certs.filter((c) => c?.expiresAt && new Date(c.expiresAt).getTime() <= limit).map((c) => ({ ...c, expired: new Date(c.expiresAt).getTime() < new Date(now).getTime() }));
}

/** Changes that crew members (same-zone miners) may hear about. */
export const CREW_VISIBLE = new Set(['identity', 'photo', 'score', 'presence']);

/** Socket rooms for a profile change of `user`. */
export function roomsFor(user, changed = []) {
  const id = String(user._id ?? user.id);
  const rooms = [`user:${id}`, 'role:admin'];
  if (user.zoneId) {
    rooms.push(`zone:${user.zoneId}:supervisors`);
    if (changed.some((c) => CREW_VISIBLE.has(c))) rooms.push(`zone:${user.zoneId}`);
  }
  return rooms;
}
