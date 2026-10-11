import crypto from 'node:crypto';

export const OTP_TTL_MS = 5 * 60_000;
export const OTP_VERIFIED_TTL_MS = 10 * 60_000;
export const OTP_COOLDOWN_MS = 30_000;
export const OTP_MAX_ATTEMPTS = 5;
export const OTP_MAX_SENDS_PER_HOUR = 5;

export const generateCode = () => String(crypto.randomInt(100000, 1000000));

export const hashCode = (uid, code) => crypto.createHash('sha256').update(`${uid}|${code}|mg-otp`).digest('hex');

export function codeMatches(uid, code, expectedHash) {
  const a = Buffer.from(hashCode(uid, code));
  const b = Buffer.from(String(expectedHash));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export const normalizeEmail = (e) => (typeof e === 'string' ? e.trim().toLowerCase() : '');

/** Decides whether a new code may be sent now. `row` is the existing OtpCode (or null). */
export function sendDecision(row, now = Date.now()) {
  if (!row) return { ok: true, sendCount: 1, windowStart: new Date(now) };
  const since = now - row.sentAt.getTime();
  if (since < OTP_COOLDOWN_MS) return { ok: false, code: 'OTP_COOLDOWN', retryAfterSec: Math.ceil((OTP_COOLDOWN_MS - since) / 1000) };
  const age = now - row.windowStart.getTime();
  const inWindow = age < 3_600_000;
  if (inWindow && row.sendCount >= OTP_MAX_SENDS_PER_HOUR) {
    return { ok: false, code: 'OTP_LIMIT', retryAfterSec: Math.ceil((3_600_000 - age) / 1000) };
  }
  return inWindow ? { ok: true, sendCount: row.sendCount + 1, windowStart: row.windowStart } : { ok: true, sendCount: 1, windowStart: new Date(now) };
}

export const otpMailText = (code) => `Your Mine Guardian code is ${code}.\nIt works once and expires in 5 minutes. If you did not try to log in or sign up, ignore this email and do not share the code.`;
