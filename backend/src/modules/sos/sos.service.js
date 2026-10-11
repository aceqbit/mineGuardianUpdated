import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { audit } from '../../core/audit.js';
import { bus } from '../../core/bus.js';
import { emitTo } from '../../core/socket.js';
import { sendSms } from '../../core/twilio.js';
import { toPoint, fromPoint } from '../../core/geo.js';
import { logger } from '../../core/logger.js';
import { SosEvent } from '../../models/SosEvent.js';
import { Zone } from '../../models/Zone.js';
import { User } from '../../models/User.js';

const istHHmm = (d) => new Date(new Date(d).getTime() + 5.5 * 3600 * 1000).toISOString().slice(11, 16);

export function sosSmsText({ name, zoneCode, at, lat, lng }) {
  const hasLoc = Number.isFinite(lat) && Number.isFinite(lng);
  const loc = hasLoc ? `${lat.toFixed(5)},${lng.toFixed(5)}` : 'unknown';
  const maps = hasLoc ? `, maps https://maps.google.com/?q=${lat.toFixed(5)},${lng.toFixed(5)}` : '';
  return `SOS: ${name}, ${zoneCode}, ${istHHmm(at)} IST, loc ${loc}${maps}`;
}

/** The cancel route accepts the server ObjectId or the original clientId (an offline SOS may not have a server id yet). */
export async function findSosByKey(key) {
  if (mongoose.isValidObjectId(key) && String(key).length === 24) {
    const byId = await SosEvent.findById(key);
    if (byId) return byId;
  }
  return SosEvent.findOne({ clientId: key });
}

const view = (s) => {
  const o = s.toJSON();
  const loc = fromPoint(s.location);
  if (loc) o.locationLatLng = loc;
  return o;
};

export async function createSos({ user, body }) {
  const existing = await SosEvent.findOne({ clientId: body.clientId });
  if (existing) return { sos: view(existing), created: false };
  const zone = user.zoneId ? await Zone.findById(user.zoneId) : null;
  if (!zone) throw new AppError(400, 'ZONE_NOT_FOUND', 'Your zone was not found');
  const hasLoc = Number.isFinite(body.lat) && Number.isFinite(body.lng);
  const triggeredAt = body.triggeredAt ? new Date(body.triggeredAt) : new Date();
  let sos;
  try {
    sos = await SosEvent.create({
      clientId: body.clientId,
      workerId: user._id,
      zoneId: zone._id,
      location: hasLoc ? toPoint(body.lat, body.lng) : undefined,
      accuracyM: body.accuracyM ?? undefined,
      triggeredAt,
      receivedAt: new Date(),
      status: 'ACTIVE',
    });
  } catch (err) {
    if (err?.code === 11000) return { sos: view(await SosEvent.findOne({ clientId: body.clientId })), created: false };
    throw err;
  }

  // Text the zone's supervisors immediately; never blocks the response.
  const text = sosSmsText({ name: user.fullName, zoneCode: zone.code, at: triggeredAt, lat: body.lat, lng: body.lng });
  User.find({ _id: { $in: zone.supervisorIds }, status: 'active' })
    .select('phone.e164')
    .then((sups) => Promise.allSettled(sups.filter((s) => s.phone?.e164).map((s) => sendSms(s.phone.e164, text))))
    .catch((err) => logger.warn({ err: err.message }, 'SOS SMS failed'));

  await audit(user, 'SOS_TRIGGERED', 'sos', sos._id, { zone: zone.code });
  bus.publish('SosTriggered', { sosId: String(sos._id) });
  emitTo([`zone:${zone._id}:supervisors`, 'role:admin'], 'sos:triggered', {
    sosId: String(sos._id),
    workerId: String(user._id),
    workerName: user.fullName,
    zoneId: String(zone._id),
    location: hasLoc ? { lat: body.lat, lng: body.lng, accuracyM: body.accuracyM ?? null } : null,
    triggeredAt: triggeredAt.toISOString(),
  });
  return { sos: view(sos), created: true };
}

export async function cancelSos({ user, key }) {
  const sos = await findSosByKey(key);
  if (!sos) throw new AppError(404, 'NOT_FOUND', 'SOS not found');
  if (String(sos.workerId) !== String(user._id)) throw new AppError(403, 'FORBIDDEN_ROLE', 'Only the worker who sent the SOS can cancel it');
  if (sos.status === 'CANCELLED') return view(sos); // idempotent
  if (sos.status !== 'ACTIVE') throw new AppError(409, 'INVALID_TRANSITION', `SOS is already ${sos.status}`);
  sos.status = 'CANCELLED';
  sos.cancelledAt = new Date();
  await sos.save();
  await audit(user, 'SOS_CANCELLED', 'sos', sos._id);
  bus.publish('SosCancelled', { sosId: String(sos._id) });
  emitTo([`zone:${sos.zoneId}:supervisors`, 'role:admin'], 'sos:cancelled', { sosId: String(sos._id), workerId: String(sos.workerId), zoneId: String(sos.zoneId) });
  return view(sos);
}
