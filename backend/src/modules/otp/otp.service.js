import { AppError } from '../../core/errors.js';
import { audit } from '../../core/audit.js';
import { env } from '../../config/env.js';
import { mailConfigured, maskEmail, sendMail } from '../../core/mailer.js';
import { OtpCode } from '../../models/OtpCode.js';
import {
  OTP_COOLDOWN_MS, OTP_MAX_ATTEMPTS, OTP_TTL_MS, OTP_VERIFIED_TTL_MS,
  codeMatches, generateCode, hashCode, normalizeEmail, otpMailText, sendDecision,
} from './otp.logic.js';

/** The login email is the identity, so the code always goes to the address the user just signed in with. */
const targetOf = (firebase) => normalizeEmail(firebase?.email);

/** Emails a fresh 6-digit code to the signed-in login email. The code is never returned by the API. */
export async function sendOtp(firebase) {
  if (!mailConfigured()) throw new AppError(503, 'OTP_NOT_CONFIGURED', 'Email verification is not set up on the server');
  const email = targetOf(firebase);
  if (!email) throw new AppError(400, 'EMAIL_REQUIRED', 'This account has no email address');

  const now = Date.now();
  const row = await OtpCode.findOne({ firebaseUid: firebase.uid });
  const d = sendDecision(row, now);
  if (!d.ok) throw new AppError(429, d.code, d.code === 'OTP_COOLDOWN' ? 'Please wait before asking for another code' : 'Too many codes requested. Try again later', { retryAfterSec: d.retryAfterSec });

  const code = generateCode();
  await OtpCode.updateOne(
    { firebaseUid: firebase.uid },
    { $set: { target: email, codeHash: hashCode(firebase.uid, code), attempts: 0, sentAt: new Date(now), windowStart: d.windowStart, sendCount: d.sendCount, verifiedAt: null, expiresAt: new Date(now + OTP_TTL_MS) } },
    { upsert: true },
  );
  const r = await sendMail(email, 'Your Mine Guardian code', otpMailText(code));
  if (r.error) {
    await OtpCode.deleteOne({ firebaseUid: firebase.uid });
    throw new AppError(502, 'OTP_SEND_FAILED', 'Could not send the code. Try again in a moment');
  }
  await audit(null, 'OTP_SENT', 'otp', firebase.uid);
  return { sent: true, to: maskEmail(email), cooldownSec: OTP_COOLDOWN_MS / 1000, expiresInSec: OTP_TTL_MS / 1000 };
}

export async function verifyOtp(firebase, code) {
  const row = await OtpCode.findOne({ firebaseUid: firebase.uid });
  if (!row || row.expiresAt.getTime() < Date.now()) throw new AppError(400, 'CODE_EXPIRED', 'That code has expired. Request a new one');
  if (row.attempts >= OTP_MAX_ATTEMPTS) {
    await OtpCode.deleteOne({ firebaseUid: firebase.uid });
    throw new AppError(429, 'TOO_MANY_ATTEMPTS', 'Too many wrong codes. Request a new one');
  }
  if (!codeMatches(firebase.uid, code, row.codeHash)) {
    await OtpCode.updateOne({ firebaseUid: firebase.uid }, { $inc: { attempts: 1 } });
    throw new AppError(400, 'WRONG_CODE', 'That code is not correct', { attemptsLeft: OTP_MAX_ATTEMPTS - (row.attempts + 1) });
  }
  await OtpCode.updateOne({ firebaseUid: firebase.uid }, { $set: { verifiedAt: new Date(), expiresAt: new Date(Date.now() + OTP_VERIFIED_TTL_MS) } });
  await audit(null, 'OTP_VERIFIED', 'otp', firebase.uid);
  return { verified: true };
}

/** Sign-up gate: this login email must have been verified in the last 10 minutes. */
export async function requireVerifiedEmail(firebase) {
  if (!env.OTP_REQUIRED) return;
  const row = await OtpCode.findOne({ firebaseUid: firebase?.uid });
  if (!row || !row.verifiedAt || row.target !== targetOf(firebase) || row.expiresAt.getTime() < Date.now()) {
    throw new AppError(403, 'EMAIL_NOT_VERIFIED', 'Verify your email address first');
  }
}

export const consumeVerifiedEmail = (firebase) => OtpCode.deleteOne({ firebaseUid: firebase.uid }).catch(() => {});
