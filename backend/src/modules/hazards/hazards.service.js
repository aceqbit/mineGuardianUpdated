import crypto from 'node:crypto';
import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { audit } from '../../core/audit.js';
import { bus } from '../../core/bus.js';
import { emitTo } from '../../core/socket.js';
import { uploadBuffer, signedUrl } from '../../core/storage.js';
import { sendSms } from '../../core/twilio.js';
import { logger, maskPhone } from '../../core/logger.js';
import { pointInPolygon, toPoint, fromPoint } from '../../core/geo.js';
import { Hazard } from '../../models/Hazard.js';
import { Zone } from '../../models/Zone.js';
import { User } from '../../models/User.js';
import { analyzeQuality, sniffImageType } from '../checkins/image-quality.js';
import { istDateString } from '../checkins/integrity.js';

export const CATEGORY_LABEL = {
  GAS_LEAK: 'Gas leak / smell',
  ROOF_FALL: 'Roof or side fall',
  FIRE_SMOKE: 'Fire or smoke',
  FLOODING: 'Water / flooding',
  ELECTRICAL: 'Electrical danger',
  EQUIPMENT_FAILURE: 'Equipment failure',
  VENTILATION_FAILURE: 'Ventilation failure',
  OTHER: 'Other',
};

const MIN_NOTE = 5;

/**
 * Pure status-transition rules. Returns null when allowed, else an error { status, code, message }.
 * OPEN -> ACKNOWLEDGED; OPEN|ACKNOWLEDGED -> CLOSED (note >= 5 chars); OPEN|ACKNOWLEDGED -> REJECTED (note required).
 */
export function checkTransition(from, to, note) {
  const text = (note ?? '').trim();
  const allowed = {
    ACKNOWLEDGED: ['OPEN'],
    CLOSED: ['OPEN', 'ACKNOWLEDGED'],
    REJECTED: ['OPEN', 'ACKNOWLEDGED'],
  };
  if (!allowed[to]) return { status: 400, code: 'VALIDATION_ERROR', message: 'status must be ACKNOWLEDGED, CLOSED or REJECTED' };
  if (to === 'CLOSED' && text.length < MIN_NOTE) return { status: 400, code: 'VALIDATION_ERROR', message: `A note of at least ${MIN_NOTE} characters is required to close a hazard` };
  if (to === 'REJECTED' && text.length < 1) return { status: 400, code: 'VALIDATION_ERROR', message: 'A note is required to reject a hazard' };
  if (!allowed[to].includes(from)) return { status: 409, code: 'INVALID_TRANSITION', message: `Cannot move a hazard from ${from} to ${to}` };
  return null;
}

export function hazardSmsText({ category, zoneCode, reporterName, at, lat, lng }) {
  const hhmm = new Date(new Date(at).getTime() + 5.5 * 3600 * 1000).toISOString().slice(11, 16);
  const loc = lat != null && lng != null ? `${lat.toFixed(5)},${lng.toFixed(5)}` : 'unknown';
  return `MINE GUARDIAN HAZARD: ${CATEGORY_LABEL[category] ?? category} in ${zoneCode} by ${reporterName} at ${hhmm} IST. Loc ${loc}. Open the app to act.`;
}

async function resolveZone(user, lat, lng) {
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    const zones = await Zone.find();
    const hit = zones.find((z) => pointInPolygon({ lat, lng }, z.polygon));
    if (hit) return hit;
  }
  const own = user.zoneId ? await Zone.findById(user.zoneId) : null;
  if (!own) throw new AppError(400, 'ZONE_NOT_FOUND', 'No zone for this report');
  return own;
}

export async function hazardView(h, { reporter } = {}) {
  const o = h.toJSON();
  o.thumbUrl = await signedUrl(h.storagePath).catch(() => null);
  o.imageUrl = o.thumbUrl;
  const loc = fromPoint(h.location);
  if (loc) o.locationLatLng = loc;
  if (reporter) o.reporterName = reporter.fullName;
  return o;
}

export async function createHazard({ user, file, body }) {
  const existing = await Hazard.findOne({ clientId: body.clientId });
  if (existing) return { hazard: await hazardView(existing, { reporter: user }), created: false };

  if (!file) throw new AppError(400, 'VALIDATION_ERROR', 'image file is required', [{ path: 'image', message: 'Required' }]);
  const buf = file.buffer;
  if (!sniffImageType(buf)) throw new AppError(400, 'UNSUPPORTED_IMAGE', 'Only JPEG or PNG photos are accepted');
  const sha = crypto.createHash('sha256').update(buf).digest('hex');
  if (sha !== body.sha256.toLowerCase()) throw new AppError(400, 'HASH_MISMATCH', 'Upload was corrupted. Please retry');
  let q;
  try {
    q = await analyzeQuality(buf, { lenient: true });
  } catch {
    throw new AppError(400, 'UNSUPPORTED_IMAGE', 'This photo could not be read');
  }
  if (!q.pass) throw new AppError(422, 'QUALITY_REJECTED', 'Photo quality is too low. Please retake', { reasons: q.reasons });

  const zone = await resolveZone(user, body.lat, body.lng);
  const id = new mongoose.Types.ObjectId();
  const storagePath = `hazards/${zone._id}/${id}.jpg`;
  await uploadBuffer(storagePath, buf, sniffImageType(buf) === 'png' ? 'image/png' : 'image/jpeg');
  const hasLoc = Number.isFinite(body.lat) && Number.isFinite(body.lng);
  const hazard = await Hazard.create({
    _id: id,
    clientId: body.clientId,
    reporterId: user._id,
    zoneId: zone._id,
    category: body.category,
    storagePath,
    location: hasLoc ? toPoint(body.lat, body.lng) : undefined,
    accuracyM: body.accuracyM ?? undefined,
    capturedAt: body.capturedAt ? new Date(body.capturedAt) : undefined,
    queuedAt: body.queuedAt ? new Date(body.queuedAt) : undefined,
    receivedAt: new Date(),
    status: 'OPEN',
  });

  // SMS to the zone's supervisors: dry run respected, never blocks the response.
  const text = hazardSmsText({ category: body.category, zoneCode: zone.code, reporterName: user.fullName, at: hazard.receivedAt, lat: body.lat, lng: body.lng });
  User.find({ _id: { $in: zone.supervisorIds }, status: 'active' })
    .select('phone.e164')
    .then((sups) => Promise.allSettled(sups.filter((s) => s.phone?.e164).map((s) => sendSms(s.phone.e164, text))))
    .catch((err) => logger.warn({ err: err.message }, `hazard SMS failed for zone ${zone.code} (${maskPhone('')})`));

  await audit(user, 'HAZARD_REPORTED', 'hazard', hazard._id, { category: body.category, zone: zone.code });
  bus.publish('HazardCreated', { hazardId: String(hazard._id) });
  const thumbUrl = await signedUrl(storagePath).catch(() => null);
  emitTo([`zone:${zone._id}:supervisors`, 'role:admin'], 'hazard:new', {
    hazardId: String(hazard._id),
    reporterId: String(user._id),
    reporterName: user.fullName,
    zoneId: String(zone._id),
    category: body.category,
    location: hasLoc ? { lat: body.lat, lng: body.lng } : null,
    capturedAt: (hazard.capturedAt || hazard.receivedAt).toISOString(),
    thumbUrl,
  });
  return { hazard: await hazardView(hazard, { reporter: user }), created: true };
}

export async function listHazards({ user, zoneId, status, limit }) {
  const q = {};
  if (user.role === 'supervisor') {
    if (zoneId && String(zoneId) !== String(user.zoneId)) throw new AppError(403, 'FORBIDDEN_ROLE', 'Not your zone');
    q.zoneId = user.zoneId;
  } else if (zoneId) {
    q.zoneId = zoneId;
  }
  if (status) q.status = status;
  const rows = await Hazard.find(q).sort({ createdAt: -1 }).limit(limit);
  const reporters = await User.find({ _id: { $in: rows.map((r) => r.reporterId) } }).select('fullName');
  const byId = new Map(reporters.map((r) => [String(r._id), r]));
  return Promise.all(rows.map((h) => hazardView(h, { reporter: byId.get(String(h.reporterId)) })));
}

export async function updateHazard({ user, id, status, note }) {
  const h = await Hazard.findById(id);
  if (!h) throw new AppError(404, 'NOT_FOUND', 'Hazard not found');
  if (user.role === 'supervisor' && String(user.zoneId) !== String(h.zoneId)) throw new AppError(403, 'FORBIDDEN_ROLE', 'Not your zone');
  const err = checkTransition(h.status, status, note);
  if (err) throw new AppError(err.status, err.code, err.message);
  const now = new Date();
  h.status = status;
  if (status === 'ACKNOWLEDGED') {
    h.acknowledgedBy = user._id;
    h.acknowledgedAt = now;
  } else {
    h.closedBy = user._id;
    h.closedAt = now;
    h.closeNote = (note ?? '').trim();
  }
  await h.save();
  await audit(user, `HAZARD_${status}`, 'hazard', h._id, { note: h.closeNote });
  bus.publish('HazardStatusChanged', { hazardId: String(h._id), status });
  emitTo([`zone:${h.zoneId}:supervisors`, 'role:admin', `user:${h.reporterId}`], 'hazard:updated', { hazardId: String(h._id), zoneId: String(h.zoneId), status, by: String(user._id) });
  const reporter = await User.findById(h.reporterId).select('fullName');
  return hazardView(h, { reporter });
}
