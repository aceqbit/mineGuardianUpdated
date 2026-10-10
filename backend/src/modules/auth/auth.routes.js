import { Router } from 'express';
import { z } from 'zod';
import { authenticate } from '../../core/auth.js';
import { AppError, asyncHandler } from '../../core/errors.js';
import { validate } from '../../core/validate.js';
import { audit } from '../../core/audit.js';
import { ROLE } from '../../contracts/enums.js';
import { User } from '../../models/User.js';
import { Zone } from '../../models/Zone.js';
import { signupSchema } from './auth.schemas.js';
import { signup } from './auth.service.js';

export const router = Router();

const TEN_MIN = 10 * 60 * 1000;

router.post(
  '/signup',
  authenticate({ allowUnregistered: true }),
  validate({ body: signupSchema }),
  asyncHandler(async (req, res) => {
    const user = await signup(req);
    res.status(201).json({ user: user.toPublic() });
  }),
);

router.get(
  '/me',
  authenticate(),
  validate({ query: z.object({ expectedRole: z.enum(ROLE).optional() }) }),
  asyncHandler(async (req, res) => {
    const user = req.user;
    const { expectedRole } = req.query;
    if (expectedRole && expectedRole !== user.role) {
      throw new AppError(403, 'ROLE_MISMATCH', `This account is registered as ${user.role}`, { actualRole: user.role });
    }
    if (!user.lastLoginAt || Date.now() - user.lastLoginAt.getTime() > TEN_MIN) {
      user.lastLoginAt = new Date();
      await user.save();
      await audit(user, 'LOGIN', 'user', user._id);
    }
    const out = { user: user.toPublic() };
    if (user.zoneId) {
      const zone = await Zone.findById(user.zoneId);
      if (zone) out.zone = { id: zone.id, code: zone.code, name: zone.name, evacExitId: zone.evacExitId ?? null };
    }
    if (user.role === 'miner' && user.zoneId) {
      const sups = await User.find({ role: 'supervisor', zoneId: user.zoneId, status: 'active' }).select('fullName phone.e164');
      out.zoneSupervisors = sups.map((s) => ({ name: s.fullName, e164: s.phone.e164 }));
    }
    res.json(out);
  }),
);
