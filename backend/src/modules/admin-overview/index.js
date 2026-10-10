import { Router } from 'express';
import mongoose from 'mongoose';
import { authenticate, requireRole } from '../../core/auth.js';
import { asyncHandler } from '../../core/errors.js';
import { Hazard } from '../../models/Hazard.js';
import { CheckIn } from '../../models/CheckIn.js';
import { User } from '../../models/User.js';
import { Zone } from '../../models/Zone.js';
import { istDayStart } from '../feed/feed.service.js';

const router = Router();
const mask = (e164) => (e164 ? `${e164.slice(0, 3)}******${e164.slice(-4)}` : '');

/** Raw collection read: Phase 1 never imports Phase 2 models; a missing collection yields null. */
async function rawCount(name, filter) {
  try {
    const cols = await mongoose.connection.db.listCollections({ name }).toArray();
    if (!cols.length) return null;
    return await mongoose.connection.collection(name).countDocuments(filter);
  } catch {
    return null;
  }
}

router.get(
  '/overview',
  authenticate(),
  requireRole('admin'),
  asyncHandler(async (_req, res) => {
    const dayStart = istDayStart();
    const [miners, supervisors, zones, openHazards, pendingReviews, decidedToday, compliantToday] = await Promise.all([
      User.countDocuments({ role: 'miner', status: 'active' }),
      User.countDocuments({ role: 'supervisor', status: 'active' }),
      Zone.find().sort({ code: 1 }),
      Hazard.countDocuments({ status: { $in: ['OPEN', 'ACKNOWLEDGED'] } }),
      rawCount('compliance_reviews', { status: 'PENDING_REVIEW' }),
      rawCount('compliance_reviews', { status: 'DECIDED', 'decision.decidedAt': { $gte: dayStart } }),
      rawCount('compliance_reviews', { status: 'DECIDED', 'decision.finalVerdict': 'COMPLIANT', 'decision.decidedAt': { $gte: dayStart } }),
    ]);
    let activeCrisis = null;
    try {
      const c = await mongoose.connection.collection('crises').findOne({ status: 'ACTIVE' });
      if (c) activeCrisis = { id: String(c._id), startedAt: c.startedAt, trigger: c.trigger, zoneIds: (c.zoneIds || []).map(String) };
    } catch {
      /* collection may not exist yet */
    }

    const zoneCards = await Promise.all(
      zones.map(async (z) => {
        const [sups, minersCount, checkedIn] = await Promise.all([
          User.find({ _id: { $in: z.supervisorIds } }).select('fullName phone.e164'),
          User.countDocuments({ role: 'miner', zoneId: z._id, status: 'active' }),
          CheckIn.distinct('workerId', { zoneId: z._id, createdAt: { $gte: dayStart } }),
        ]);
        return {
          id: String(z._id), code: z.code, name: z.name, evacExitId: z.evacExitId ?? null,
          supervisors: sups.map((s) => ({ id: String(s._id), fullName: s.fullName, phoneMasked: mask(s.phone?.e164) })),
          minersCount, checkedInToday: checkedIn.length,
        };
      }),
    );

    res.json({
      counts: { workers: miners, supervisors, zones: zones.length },
      openHazards,
      todayCompliancePct: decidedToday ? Math.round((100 * (compliantToday ?? 0)) / decidedToday) : null,
      pendingReviews,
      activeCrisis,
      zones: zoneCards,
    });
  }),
);

router.get(
  '/supervisors',
  authenticate(),
  requireRole('admin'),
  asyncHandler(async (_req, res) => {
    const sups = await User.find({ role: 'supervisor', status: 'active' }).sort({ fullName: 1 });
    res.json(sups.map((s) => ({ id: String(s._id), fullName: s.fullName, zoneId: s.zoneId ? String(s.zoneId) : null, phoneMasked: mask(s.phone?.e164) })));
  }),
);

export default { name: 'admin-overview', basePath: '/api/admin', router };
