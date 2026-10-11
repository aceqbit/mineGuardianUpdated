import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { signedUrl } from '../../core/storage.js';
import { fromPoint } from '../../core/geo.js';
import { CheckIn } from '../../models/CheckIn.js';
import { Hazard } from '../../models/Hazard.js';
import { SosEvent } from '../../models/SosEvent.js';
import { User } from '../../models/User.js';
import { Zone } from '../../models/Zone.js';
import { istDateString } from '../checkins/integrity.js';
import { reviewSummaries, summarizeReview } from '../checkins/checkins.service.js';

/** Start of the current IST day as a UTC Date. */
export function istDayStart(now = new Date()) {
  return new Date(`${istDateString(now)}T00:00:00+05:30`);
}

export async function resolveFeedZone(user, zoneId) {
  if (user.role === 'supervisor') {
    const id = zoneId || String(user.zoneId);
    if (id !== String(user.zoneId)) throw new AppError(403, 'FORBIDDEN_ROLE', 'You can only view your own zone');
    return Zone.findById(id);
  }
  if (!zoneId) throw new AppError(400, 'VALIDATION_ERROR', 'zoneId is required', [{ path: 'zoneId', message: 'Required' }]);
  return Zone.findById(zoneId);
}

export async function supervisorSnapshot(user, zoneIdParam) {
  const zone = await resolveFeedZone(user, zoneIdParam);
  if (!zone) throw new AppError(404, 'NOT_FOUND', 'Zone not found');
  const dayStart = istDayStart();
  const since24h = new Date(Date.now() - 24 * 3600 * 1000);

  const [miners, todays, hazards, sos] = await Promise.all([
    User.find({ role: 'miner', zoneId: zone._id, status: 'active' }).sort({ fullName: 1 }),
    CheckIn.find({ zoneId: zone._id, createdAt: { $gte: dayStart } }).sort({ createdAt: -1 }).limit(50),
    Hazard.find({ zoneId: zone._id, $or: [{ status: { $in: ['OPEN', 'ACKNOWLEDGED'] } }, { createdAt: { $gte: since24h } }] }).sort({ createdAt: -1 }).limit(100),
    SosEvent.find({ zoneId: zone._id, status: 'ACTIVE' }).sort({ createdAt: -1 }),
  ]);

  const reviews = await reviewSummaries(todays.map((c) => c._id));
  const byWorker = new Map(miners.map((m) => [String(m._id), m]));

  const latestByWorker = new Map();
  for (const ci of todays) if (!latestByWorker.has(String(ci.workerId))) latestByWorker.set(String(ci.workerId), ci);

  const countByWorker = new Map();
  for (const ci of todays) countByWorker.set(String(ci.workerId), (countByWorker.get(String(ci.workerId)) ?? 0) + 1);

  const workers = await Promise.all(
    miners.map(async (m) => {
      const ci = latestByWorker.get(String(m._id));
      const rv = ci ? summarizeReview(reviews.get(String(ci._id))) : undefined;
      return {
        id: String(m._id), fullName: m.fullName, employeeId: m.employeeId, shift: m.shift, phoneE164: m.phone?.e164,
        today: {
          status: ci ? ci.status : 'NOT_CHECKED_IN', verdict: rv?.verdict ?? null, finalVerdict: rv?.finalVerdict ?? null,
          checkInId: ci ? String(ci._id) : null, capturedAt: ci ? (ci.capturedAt || ci.receivedAt)?.toISOString() : null,
          thumbUrl: ci ? await signedUrl(ci.storagePath).catch(() => null) : null, count: countByWorker.get(String(m._id)) ?? 0,
        },
      };
    }),
  );

  const checkins = await Promise.all(
    todays.map(async (ci) => {
      const w = byWorker.get(String(ci.workerId));
      const rv = reviews.get(String(ci._id));
      const s = summarizeReview(rv);
      return {
        id: String(ci._id), checkInId: String(ci._id), workerId: String(ci.workerId), workerName: w?.fullName ?? 'Worker', zoneId: String(ci.zoneId),
        thumbUrl: await signedUrl(ci.storagePath).catch(() => null), integrityFlags: ci.integrityFlags, capturedAt: (ci.capturedAt || ci.receivedAt)?.toISOString(),
        status: ci.status,
        review: s && { ...s, criticality: rv?.ai?.criticality, summary: rv?.ai?.summary, emergency: rv?.ai?.emergency },
      };
    }),
  );

  const reporterIds = [...new Set(hazards.map((h) => String(h.reporterId)))];
  const reporters = await User.find({ _id: { $in: reporterIds } }).select('fullName');
  const rById = new Map(reporters.map((r) => [String(r._id), r.fullName]));
  const hazardOut = await Promise.all(
    hazards.map(async (h) => ({
      ...h.toJSON(), id: String(h._id), hazardId: String(h._id), reporterName: rById.get(String(h.reporterId)) ?? 'Worker',
      thumbUrl: await signedUrl(h.storagePath).catch(() => null), locationLatLng: fromPoint(h.location),
    })),
  );

  const workerNames = new Map((await User.find({ _id: { $in: sos.map((s) => s.workerId) } }).select('fullName phone.e164')).map((u) => [String(u._id), u]));
  const sosOut = sos.map((s) => ({
    ...s.toJSON(), id: String(s._id), sosId: String(s._id), workerName: workerNames.get(String(s.workerId))?.fullName ?? 'Worker',
    workerPhone: workerNames.get(String(s.workerId))?.phone?.e164, locationLatLng: fromPoint(s.location),
  }));

  return {
    zone: { id: String(zone._id), code: zone.code, name: zone.name, requiredPpe: zone.requiredPpe, shiftWindows: zone.shiftWindows },
    workers, checkins, hazards: hazardOut, sos: sosOut,
  };
}

export const isObjectId = (v) => mongoose.isValidObjectId(v);
