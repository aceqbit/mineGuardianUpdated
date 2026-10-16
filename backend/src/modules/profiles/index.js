// Profile manager API (CLAUDE.md section 23.2). Every change that touches a profile is pushed as `profile:updated`.
import { Router } from 'express';
import mongoose from 'mongoose';
import { z } from 'zod';
import { isValidPhoneNumber } from 'libphonenumber-js';
import { authenticate } from '../../core/auth.js';
import { asyncHandler } from '../../core/errors.js';
import { validate, objectId, isoDate } from '../../core/validate.js';
import { audit } from '../../core/audit.js';
import { publish, subscribe } from '../../core/bus.js';
import { emitTo } from '../../core/socket.js';
import { logger } from '../../core/logger.js';
import { ROLE, SHIFT, USER_STATUS } from '../../contracts/enums.js';
import { CheckIn } from '../../models/CheckIn.js';
import { Hazard } from '../../models/Hazard.js';
import { SosEvent } from '../../models/SosEvent.js';
import { User } from '../../models/User.js';
import { roomsFor } from './profiles.logic.js';
import { getProfile, listProfiles, patchProfile } from './profiles.service.js';

const router = Router();
const userParams = z.object({ userId: objectId });

router.get(
  '/',
  authenticate(),
  validate({
    query: z.object({
      role: z.enum(ROLE).optional(),
      zoneId: objectId.optional(),
      q: z.string().trim().max(60).optional(),
      limit: z.coerce.number().int().min(1).max(200).default(100),
      cursor: z.coerce.number().int().min(0).default(0),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await listProfiles(req.user, req.query));
  }),
);

router.get(
  '/:userId',
  authenticate(),
  validate({ params: userParams }),
  asyncHandler(async (req, res) => {
    res.json({ profile: await getProfile(req.user, req.params.userId) });
  }),
);

export const patchSchema = z
  .object({
    designation: z.string().trim().max(60).nullable(),
    bloodGroup: z.enum(['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']).nullable(),
    experienceYears: z.number().int().min(0).max(60).nullable(),
    dateOfJoining: isoDate.nullable(),
    medicalNotes: z.string().trim().max(500).nullable(),
    certifications: z.array(z.object({ name: z.string().trim().min(2).max(80), issuedAt: isoDate.optional(), expiresAt: isoDate.optional() })).max(20),
    status: z.enum(USER_STATUS),
    shift: z.enum(SHIFT),
    zoneId: objectId,
    phoneE164: z.string().trim().refine((v) => /^\+\d{8,15}$/.test(v) && isValidPhoneNumber(v), 'Invalid E.164 number').nullable(),
  })
  .partial()
  .strict()
  .refine((v) => Object.keys(v).length > 0, 'Nothing to update');

router.patch(
  '/:userId',
  authenticate(),
  validate({ params: userParams, body: patchSchema }),
  asyncHandler(async (req, res) => {
    const { user, changed, prevZone, fields } = await patchProfile(req.user, req.params.userId, req.body);
    // Field names only: values (medical notes, phone) never go to the audit log.
    await audit(req.user, 'PROFILE_UPDATED', 'user', user._id, { fields });
    await notify(user, changed, prevZone);
    res.json({ profile: await getProfile(req.user, req.params.userId) });
  }),
);

/** Publish + push one profile change. Never throws. */
export async function notify(userOrId, changed, prevZone = null) {
  try {
    const u = typeof userOrId === 'object' && userOrId?.role ? userOrId : await User.findById(userOrId).select('role zoneId');
    if (!u) return;
    const userId = String(u._id);
    publish('ProfileChanged', { userId, changed });
    const rooms = new Set(roomsFor(u, changed));
    if (prevZone && prevZone !== String(u.zoneId)) for (const r of roomsFor({ _id: u._id, zoneId: prevZone }, changed)) rooms.add(r);
    // One emit over the union of rooms: socket.io delivers once per socket.
    emitTo([...rooms], 'profile:updated', { userId, changed });
  } catch (err) {
    logger.warn({ err: err.message }, 'profile notify failed');
  }
}

const raw = (name) => mongoose.connection.collection(name);

async function init() {
  subscribe('CheckInCreated', async ({ data }) => {
    const c = await CheckIn.findById(data.checkInId).select('workerId');
    if (c) await notify(c.workerId, ['today', 'photo', 'calendar']);
  });
  subscribe('ComplianceReviewed', async ({ data }) => {
    if (data.workerId) await notify(data.workerId, ['today', 'calendar']);
    const r = await raw('compliance_reviews').findOne({ _id: new mongoose.Types.ObjectId(String(data.reviewId)) }, { projection: { 'decision.decidedBy': 1 } }).catch(() => null);
    if (r?.decision?.decidedBy) await notify(r.decision.decidedBy, ['supervisorStats']);
  });
  for (const ev of ['HazardCreated', 'HazardStatusChanged']) {
    subscribe(ev, async ({ data }) => {
      const h = await Hazard.findById(data.hazardId).select('reporterId');
      if (h) await notify(h.reporterId, ['hazards']);
    });
  }
  for (const ev of ['SosTriggered', 'SosCancelled']) {
    subscribe(ev, async ({ data }) => {
      const s = await SosEvent.findById(data.sosId).select('workerId');
      if (s) await notify(s.workerId, ['sos']);
    });
  }
  for (const ev of ['CrisisActivated', 'CrisisResolved']) {
    subscribe(ev, async ({ data }) => {
      const c = await raw('crises').findOne({ _id: new mongoose.Types.ObjectId(String(data.crisisId)) }, { projection: { zoneIds: 1 } }).catch(() => null);
      if (!c?.zoneIds?.length) return;
      const users = await User.find({ zoneId: { $in: c.zoneIds }, status: 'active' }).select('role zoneId');
      for (const u of users) await notify(u, ['crisis']);
    });
  }
}

export default { name: 'profiles', basePath: '/api/profiles', router, init };
