// AI voice agent calls (CLAUDE.md section 23.5). Tapping a number calls POST /api/voice/call: every existing dialling
// guard applies (E.164, emergency-number blocklist, TWILIO_CALL_ALLOWLIST, dry run), then Twilio either speaks an
// AI-written briefing (`say`) or connects a live AI conversation (`relay`, ConversationRelay over /voice/relay).
import crypto from 'node:crypto';
import express, { Router } from 'express';
import mongoose from 'mongoose';
import { z } from 'zod';
import { authenticate } from '../../core/auth.js';
import { AppError, asyncHandler } from '../../core/errors.js';
import { validate, objectId } from '../../core/validate.js';
import { audit } from '../../core/audit.js';
import { emitTo } from '../../core/socket.js';
import { logger, maskPhone } from '../../core/logger.js';
import { endCall, placeCall, validTwilioSignature } from '../../core/twilio.js';
import { env } from '../../config/env.js';
import { User } from '../../models/User.js';
import { VoiceCall } from '../../models/VoiceCall.js';
// The emergency-number blocklist has exactly one home (contacts.logic.js, CLAUDE.md section 13). Importing it is a
// deliberate exception to "add-ons never import other modules": a second copy could drift and dial a real 112.
import { assertSafeDialTarget } from '../contacts/contacts.logic.js';
import { briefing, greeting, reply } from './agent.js';
import { buildPacket } from './context.js';
import { attachRelay } from './relay.js';
import { canCall, isFinal, relayTwiml, relayUrl, sayTwiml, statusFromTwilio, statusUrl, takeCooldown } from './voice.logic.js';

const router = Router();
const cooldowns = new Map();
/** callId -> { packet, targetLabel, callerId } for live relay calls (memory only; transcripts are never stored). */
const sessions = new Map();

const notify = (call) =>
  emitTo([`user:${call.callerId}`], 'voice:call_status', { callId: String(call._id), status: call.status, targetLabel: call.targetLabel, dryRun: call.dryRun, mode: call.mode });

async function setStatus(callId, status, extra = {}) {
  const call = await VoiceCall.findById(callId);
  if (!call || (isFinal(call.status) && call.status !== status)) return call;
  if (call.status === status && !Object.keys(extra).length) return call;
  call.status = status;
  Object.assign(call, extra);
  if (isFinal(status)) {
    call.endedAt = new Date();
    sessions.delete(String(call._id));
  }
  await call.save();
  notify(call);
  return call;
}

async function resolveTarget(caller, targetType, targetId) {
  if (targetType === 'contact') {
    const c = await mongoose.connection.collection('emergency_contacts').findOne({ _id: new mongoose.Types.ObjectId(targetId), active: { $ne: false } });
    if (!c) throw new AppError(404, 'NOT_FOUND', 'Contact not found');
    if (!canCall(caller, 'contact', c)) throw new AppError(403, 'FORBIDDEN_SCOPE', 'You cannot call emergency contacts');
    return { number: c.dialE164, label: c.name };
  }
  const u = await User.findById(targetId).select('fullName role zoneId status phone');
  if (!u || u.status !== 'active') throw new AppError(404, 'NOT_FOUND', 'Person not found');
  if (!canCall(caller, 'user', u)) throw new AppError(403, 'FORBIDDEN_SCOPE', 'You cannot call this person');
  if (!u.phone?.e164) throw new AppError(400, 'NO_PHONE', `${u.fullName} has no contact number. An admin can add one in their profile.`);
  return { number: u.phone.e164, label: `${u.fullName} (${u.role})` };
}

router.post(
  '/call',
  authenticate(),
  validate({ body: z.object({ targetType: z.enum(['user', 'contact']), targetId: objectId, reason: z.string().trim().max(200).optional() }).strict() }),
  asyncHandler(async (req, res) => {
    const { targetType, targetId, reason } = req.body;
    const { number, label } = await resolveTarget(req.user, targetType, targetId);
    assertSafeDialTarget(number); // 400 UNSAFE_DIAL_TARGET for 112 / 100 / short codes / invalid numbers
    const wait = takeCooldown(cooldowns, String(req.user._id), targetId);
    if (wait > 0) throw new AppError(429, 'CALL_COOLDOWN', `You just called ${label}. Try again in ${wait} s.`, { retryAfterSec: wait });

    const packet = await buildPacket(req.user, { reason });
    const callId = new mongoose.Types.ObjectId();
    const token = crypto.randomBytes(18).toString('base64url');
    const wsUrl = env.VOICE_AGENT_MODE === 'relay' ? relayUrl(env.PUBLIC_BASE_URL, String(callId), token) : null;
    if (env.VOICE_AGENT_MODE === 'relay' && !wsUrl) logger.warn('VOICE_AGENT_MODE=relay needs a public https PUBLIC_BASE_URL; falling back to say');
    const mode = wsUrl ? 'relay' : 'say';

    let twiml;
    let briefingChars;
    if (mode === 'relay') {
      const hello = await greeting(packet, label);
      twiml = relayTwiml(wsUrl, hello);
      briefingChars = hello.length;
      sessions.set(String(callId), { packet, targetLabel: label, callerId: String(req.user._id) });
    } else {
      const b = await briefing(packet, label);
      twiml = sayTwiml(b.text);
      briefingChars = b.text.length;
    }

    const r = await placeCall(number, { twiml, statusCallback: statusUrl(env.PUBLIC_BASE_URL, String(callId)) });
    const status = r.error ? 'FAILED' : r.dryRun ? 'DRY_RUN' : 'QUEUED';
    const call = await VoiceCall.create({
      _id: callId, callerId: req.user._id, targetType, targetId, targetLabel: label, toMasked: maskPhone(number), mode, status,
      sid: r.sid, dryRun: Boolean(r.dryRun), reason, briefingChars, relayToken: token, error: r.error, endedAt: isFinal(status) ? new Date() : undefined,
    });
    if (isFinal(status)) sessions.delete(String(callId));
    await audit(req.user, 'VOICE_CALL_PLACED', 'voice_call', call._id, { targetType, mode, status, dryRun: call.dryRun });
    notify(call);
    if (r.error === 'NOT_ALLOWLISTED') throw new AppError(403, 'NOT_ALLOWLISTED', `${label} is not in TWILIO_CALL_ALLOWLIST, so no real call was placed`, { callId: String(call._id) });
    if (r.error) throw new AppError(502, 'CALL_FAILED', 'Twilio could not place the call', { callId: String(call._id) });
    res.status(201).json({ callId: String(call._id), status, mode, dryRun: call.dryRun, targetLabel: label, statusUpdates: Boolean(statusUrl(env.PUBLIC_BASE_URL, 'x')) });
  }),
);

router.post(
  '/call/:callId/hangup',
  authenticate(),
  validate({ params: z.object({ callId: objectId }) }),
  asyncHandler(async (req, res) => {
    const call = await VoiceCall.findById(req.params.callId);
    if (!call) throw new AppError(404, 'NOT_FOUND', 'Call not found');
    if (String(call.callerId) !== String(req.user._id) && req.user.role !== 'admin') throw new AppError(403, 'FORBIDDEN_SCOPE', 'Not your call');
    if (!isFinal(call.status)) {
      await endCall(call.sid);
      await setStatus(call._id, 'COMPLETED');
    }
    const fresh = await VoiceCall.findById(call._id);
    res.json({ callId: String(fresh._id), status: fresh.status });
  }),
);

/** Twilio status webhook: no bearer token, so the X-Twilio-Signature must verify against the URL we gave Twilio. */
router.post(
  '/status',
  express.urlencoded({ extended: false, limit: '32kb' }),
  asyncHandler(async (req, res) => {
    const url = `${new URL(env.PUBLIC_BASE_URL).origin}${req.originalUrl}`;
    if (!validTwilioSignature(req.get('X-Twilio-Signature'), url, req.body ?? {})) throw new AppError(403, 'BAD_SIGNATURE', 'Twilio signature check failed');
    const callId = String(req.query.callId ?? '');
    const status = statusFromTwilio(req.body?.CallStatus);
    if (mongoose.isValidObjectId(callId) && status) await setStatus(callId, status);
    res.type('text/xml').send('<Response/>');
  }),
);

async function authorize(callId, token) {
  if (!mongoose.isValidObjectId(callId) || !token) return null;
  const call = await VoiceCall.findById(callId).select('+relayToken');
  const s = sessions.get(String(callId));
  if (!call || !s || isFinal(call.status) || call.relayToken?.length !== token.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(call.relayToken), Buffer.from(token))) return null;
  return { ...s, callId: String(callId), turns: 0 };
}

async function init({ io }) {
  if (!io?.httpServer) return logger.warn('voice: no HTTP server to attach /voice/relay to; relay mode unavailable');
  attachRelay(io.httpServer, {
    authorize,
    reply: (session, history, text, onToken) => reply(session.packet, history, text, onToken),
    onStatus: (session, status) => {
      setStatus(session.callId, status, status === 'COMPLETED' ? { turns: session.turns ?? 0 } : {}).catch((err) => logger.warn({ err: err.message }, 'voice status update failed'));
    },
    maxSec: env.VOICE_AGENT_MAX_SEC ?? 180,
  });
}

export default { name: 'voice', basePath: '/api/voice', router, init };
