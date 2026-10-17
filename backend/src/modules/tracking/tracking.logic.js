// Pure rules of live tracking (CLAUDE.md section 23.3). Unit-tested; no I/O.

/** LIVE < staleSec, STALE < offlineSec, else OFFLINE. */
export function presenceOf(ts, now, staleSec, offlineSec) {
  if (!ts) return 'OFFLINE';
  const age = (now - new Date(ts).getTime()) / 1000;
  if (age < staleSec) return 'LIVE';
  return age < offlineSec ? 'STALE' : 'OFFLINE';
}

/** The public shape of one tracked person (what admins / zone supervisors receive). */
export function toWire(e, now, staleSec, offlineSec) {
  return {
    userId: e.userId, name: e.name, employeeId: e.employeeId, role: e.role, zoneId: e.zoneId,
    lat: e.lat, lng: e.lng, accuracyM: e.accuracyM, headingDeg: e.headingDeg ?? null, speedMps: e.speedMps ?? null,
    source: e.source ?? 'GPS', tunnelId: e.tunnelId ?? null, sosId: e.sosId ?? null,
    presence: presenceOf(e.ts, now, staleSec, offlineSec), ts: e.ts,
  };
}

/**
 * Split the dirty entries into emits: every entry to `role:admin`, each entry also to its own
 * `zone:<id>:supervisors` room (a supervisor never receives another zone's people).
 */
export function planEmits(entries, now, staleSec, offlineSec) {
  if (!entries.length) return [];
  const wire = entries.map((e) => toWire(e, now, staleSec, offlineSec));
  const out = [{ room: 'role:admin', positions: wire }];
  const byZone = new Map();
  for (const w of wire) {
    if (!w.zoneId) continue;
    if (!byZone.has(w.zoneId)) byZone.set(w.zoneId, []);
    byZone.get(w.zoneId).push(w);
  }
  for (const [zoneId, positions] of byZone) out.push({ room: `zone:${zoneId}:supervisors`, positions });
  return out;
}

/** Ids whose presence band changed since the last sweep; `last` is a Map(userId -> presence) and is updated. */
export function presenceChanges(entries, last, now, staleSec, offlineSec) {
  const changed = [];
  for (const e of entries) {
    const p = presenceOf(e.ts, now, staleSec, offlineSec);
    if (last.get(e.userId) !== p) {
      last.set(e.userId, p);
      changed.push(e.userId);
    }
  }
  return changed;
}

/** Who may read the live snapshot, and for which zone. Returns { zoneId|null } or throws-style { error }. */
export function snapshotScope(user, zoneId) {
  if (user.role === 'admin') return { zoneId: zoneId ?? null };
  if (user.role === 'supervisor') {
    if (zoneId && String(zoneId) !== String(user.zoneId)) return { error: 'FORBIDDEN_SCOPE' };
    return { zoneId: String(user.zoneId) };
  }
  return { error: 'FORBIDDEN_ROLE' };
}

/** ORS foot-walking response (GeoJSON) -> { distanceM, durationSec, coordinates[[lng,lat]] } or null. */
export function parseOrs(json) {
  const f = json?.features?.[0];
  const s = f?.properties?.summary;
  const coords = f?.geometry?.coordinates;
  if (!s || !Array.isArray(coords) || coords.length < 2) return null;
  return { distanceM: Math.round(s.distance ?? 0), durationSec: Math.round(s.duration ?? 0), coordinates: coords.map(([lng, lat]) => [lng, lat]) };
}

/** Hazard row -> the minimal shape phones route around (null without a location). */
export function routingHazard(h) {
  const c = h?.location?.coordinates;
  if (!Array.isArray(c) || c.length < 2) return null;
  return {
    id: String(h._id), category: h.category, status: h.status, zoneId: h.zoneId ? String(h.zoneId) : null,
    severity: h.ai?.severity ?? null, severityConfidence: h.ai?.severityConfidence ?? null,
    locationLatLng: { lat: c[1], lng: c[0] }, createdAt: h.createdAt ? new Date(h.createdAt).toISOString() : null,
  };
}
