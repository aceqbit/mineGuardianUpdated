import test from 'node:test';
import assert from 'node:assert/strict';
import { codeMatches, generateCode, hashCode, normalizeEmail, otpMailText, sendDecision, OTP_COOLDOWN_MS } from '../src/modules/otp/otp.logic.js';
import { maskEmail } from '../src/core/mailer.js';
import { targetAllowed } from '../src/core/twilio.js';

test('generateCode is always 6 digits', () => {
  for (let i = 0; i < 500; i++) assert.match(generateCode(), /^\d{6}$/);
});

test('code hash matches only the right code and uid', () => {
  const h = hashCode('uid1', '123456');
  assert.equal(codeMatches('uid1', '123456', h), true);
  assert.equal(codeMatches('uid1', '123457', h), false);
  assert.equal(codeMatches('uid2', '123456', h), false);
});

test('emails are normalised and masked for display and logs', () => {
  assert.equal(normalizeEmail('  Me@Gmail.COM '), 'me@gmail.com');
  assert.equal(normalizeEmail(undefined), '');
  assert.equal(maskEmail('ashwin@gmail.com'), 'a***@gmail.com');
});

test('the mail says what the code is for and never asks to share it', () => {
  const t = otpMailText('654321');
  assert.match(t, /654321/);
  assert.match(t, /expires in 5 minutes/);
  assert.match(t, /do not share/i);
});

test('send decision: first send, cooldown, hourly cap, window reset', () => {
  const now = Date.now();
  assert.equal(sendDecision(null, now).ok, true);
  const row = (agoMs, count, winAgoMs) => ({ sentAt: new Date(now - agoMs), windowStart: new Date(now - winAgoMs), sendCount: count });
  const cool = sendDecision(row(10_000, 1, 10_000), now);
  assert.equal(cool.ok, false);
  assert.equal(cool.code, 'OTP_COOLDOWN');
  assert.equal(cool.retryAfterSec, 20);
  assert.equal(sendDecision(row(OTP_COOLDOWN_MS + 1, 1, 60_000), now).sendCount, 2);
  assert.equal(sendDecision(row(60_000, 5, 120_000), now).code, 'OTP_LIMIT');
  const reset = sendDecision(row(60_000, 5, 3_700_000), now);
  assert.equal(reset.ok, true);
  assert.equal(reset.sendCount, 1);
});

test('live Twilio only reaches allowlisted numbers; dry run reaches anyone', () => {
  assert.equal(targetAllowed('+919876500011', { dryRun: true, list: [] }), true);
  assert.equal(targetAllowed('+919876500011', { dryRun: false, list: [] }), false);
  assert.equal(targetAllowed('+917305093646', { dryRun: false, list: ['+917305093646'] }), true);
  assert.equal(targetAllowed('+919876500011', { dryRun: false, list: ['+917305093646'] }), false);
});
