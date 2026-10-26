import { v4 as uuid } from 'uuid';
import { parsePhoneNumberFromString } from 'libphonenumber-js/max';
import twilioLib from 'twilio';
import { env } from '../config/env.js';
import { logger, maskPhone } from './logger.js';

let client;
const hasCreds = () => Boolean(env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN && env.TWILIO_FROM_NUMBER);
const getClient = () => (client ??= twilioLib(env.TWILIO_ACCOUNT_SID, env.TWILIO_AUTH_TOKEN));
const dry = () => env.TWILIO_DRY_RUN || !hasCreds();

/** Comma-separated E.164 numbers the server may call or text when TWILIO_DRY_RUN=false. Empty list = nothing may be dialled. */
export const allowedTargets = () => String(env.TWILIO_CALL_ALLOWLIST || '').split(',').map((s) => s.trim()).filter(Boolean);
export const targetAllowed = (to, { dryRun, list }) => dryRun || list.includes(to);

const validE164 = (n) => {
  if (typeof n !== 'string' || !/^\+[1-9]\d{6,14}$/.test(n)) return false;
  return Boolean(parsePhoneNumberFromString(n));
};

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function buildTwiml(text) {
  const t = esc(text);
  return `<Response><Say language="en-IN">${t}</Say><Pause length="1"/><Say language="en-IN">${t}</Say></Response>`;
}

export async function sendSms(to, body) {
  try {
    if (!validE164(to)) return { error: 'INVALID_E164' };
    if (!targetAllowed(to, { dryRun: dry(), list: allowedTargets() })) {
      logger.warn(`twilio sms refused: ${maskPhone(to)} is not in TWILIO_CALL_ALLOWLIST`);
      return { error: 'NOT_ALLOWLISTED' };
    }
    if (dry()) {
      logger.info(`[TWILIO DRY RUN] SMS to ${maskPhone(to)}: ${String(body).slice(0, 120)}`);
      return { sid: `DRYRUN-${uuid()}`, dryRun: true };
    }
    const m = await getClient().messages.create({ to, from: env.TWILIO_FROM_NUMBER, body });
    return { sid: m.sid };
  } catch (err) {
    logger.warn({ err: err.message }, 'twilio sms failed');
    return { error: err.message };
  }
}

export async function makeCall(to, text) {
  try {
    if (!validE164(to)) return { error: 'INVALID_E164' };
    if (!targetAllowed(to, { dryRun: dry(), list: allowedTargets() })) {
      logger.warn(`twilio call refused: ${maskPhone(to)} is not in TWILIO_CALL_ALLOWLIST`);
      return { error: 'NOT_ALLOWLISTED' };
    }
    if (dry()) {
      logger.info(`[TWILIO DRY RUN] CALL to ${maskPhone(to)}: ${String(text).slice(0, 120)}`);
      return { sid: `DRYRUN-${uuid()}`, dryRun: true };
    }
    const c = await getClient().calls.create({ to, from: env.TWILIO_FROM_NUMBER, twiml: buildTwiml(text) });
    return { sid: c.sid };
  } catch (err) {
    logger.warn({ err: err.message }, 'twilio call failed');
    return { error: err.message };
  }
}

/**
 * Add-on X5: a call with caller-built TwiML (AI voice agent) and an optional status callback.
 * Same guards as makeCall: valid E.164, TWILIO_CALL_ALLOWLIST when live, dry run by default. Never throws.
 */
export async function placeCall(to, { twiml, statusCallback } = {}) {
  try {
    if (!validE164(to)) return { error: 'INVALID_E164' };
    if (!targetAllowed(to, { dryRun: dry(), list: allowedTargets() })) {
      logger.warn(`twilio call refused: ${maskPhone(to)} is not in TWILIO_CALL_ALLOWLIST`);
      return { error: 'NOT_ALLOWLISTED' };
    }
    if (dry()) {
      logger.info(`[TWILIO DRY RUN] AI CALL to ${maskPhone(to)} (${String(twiml).length} chars of TwiML)`);
      return { sid: `DRYRUN-${uuid()}`, dryRun: true };
    }
    const opts = { to, from: env.TWILIO_FROM_NUMBER, twiml };
    if (statusCallback) Object.assign(opts, { statusCallback, statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'], statusCallbackMethod: 'POST' });
    const c = await getClient().calls.create(opts);
    return { sid: c.sid };
  } catch (err) {
    logger.warn({ err: err.message }, 'twilio ai call failed');
    return { error: err.message };
  }
}

/** Hangs up a live call. Dry-run sids are a no-op. Never throws. */
export async function endCall(sid) {
  try {
    if (!sid || String(sid).startsWith('DRYRUN-') || dry()) return { ok: true, dryRun: true };
    await getClient().calls(sid).update({ status: 'completed' });
    return { ok: true };
  } catch (err) {
    logger.warn({ err: err.message }, 'twilio hangup failed');
    return { error: err.message };
  }
}

/** Twilio webhook signature check (X-Twilio-Signature). False without an auth token. */
export function validTwilioSignature(signature, url, params) {
  if (!env.TWILIO_AUTH_TOKEN || !signature) return false;
  try {
    return twilioLib.validateRequest(env.TWILIO_AUTH_TOKEN, signature, url, params);
  } catch {
    return false;
  }
}
