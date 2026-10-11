import { Router } from 'express';
import { z } from 'zod';
import { authenticate } from '../../core/auth.js';
import { asyncHandler } from '../../core/errors.js';
import { validate } from '../../core/validate.js';
import { sendOtp, verifyOtp } from './otp.service.js';

const router = Router();

// Both calls work for a signed-in Firebase identity that may not have a profile yet (sign-up). The code goes to that identity's email.
router.post('/send', authenticate({ allowUnregistered: true }), asyncHandler(async (req, res) => res.json(await sendOtp(req.firebase))));

router.post(
  '/verify',
  authenticate({ allowUnregistered: true }),
  validate({ body: z.object({ code: z.string().regex(/^\d{6}$/, 'Enter the 6-digit code') }).strict() }),
  asyncHandler(async (req, res) => res.json(await verifyOtp(req.firebase, req.body.code))),
);

export default { name: 'otp', basePath: '/api/auth/otp', router };
