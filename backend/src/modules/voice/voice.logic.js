// Pure rules of the AI voice agent (CLAUDE.md section 23.5). Unit-tested; no I/O.

export const VOICE_MAX = 450;
export const COOLDOWN_MS = 30_000;
export const MAX_TURNS = 8;

const sameZone = (a, b) => a?.zoneId && b?.zoneId && String(a.zoneId) === String(b.zoneId);

/**
 * May `caller` start an AI call to `target`?
 * miner -> own zone's supervisors and any admin; supervisor -> own zone's people, any admin, contacts;
 * admin -> anyone and contacts. Never yourself.
 */
export function canCall(caller, targetType, target) {
  if (!caller || !target) return false;
  if (targetType === 'contact') return caller.role === 'supervisor' || caller.role === 'admin';
  if (String(caller._id ?? caller.id) === String(target._id ?? target.id)) return false;
  if (caller.role === 'admin') return true;
  if (target.role === 'admin') return true;
  if (caller.role === 'supervisor') return Boolean(sameZone(caller, target));
  if (caller.role === 'miner') return target.role === 'supervisor' && Boolean(sameZone(caller, target));
  return false;
}

/** Cooldown book: Map(key -> last call ms). Returns seconds to wait (0 = go) and records the call when allowed. */
export function takeCooldown(book, callerId, targetId, now = Date.now(), ms = COOLDOWN_MS) {
  const key = `${callerId}:${targetId}`;
  const last = book.get(key);
  if (last && now - last < ms) return Math.ceil((ms - (now - last)) / 1000);
  book.set(key, now);
  return 0;
}

/** Twilio CallStatus -> VOICE_CALL_STATUS. */
export function statusFromTwilio(s) {
  switch (String(s || '').toLowerCase()) {
    case 'queued':
    case 'initiated':
      return 'QUEUED';
    case 'ringing':
      return 'RINGING';
    case 'in-progress':
    case 'answered':
      return 'IN_PROGRESS';
    case 'completed':
      return 'COMPLETED';
    case 'busy':
    case 'failed':
    case 'no-answer':
    case 'canceled':
      return 'FAILED';
    default:
      return null;
  }
}

export const isFinal = (s) => s === 'COMPLETED' || s === 'FAILED' || s === 'DRY_RUN';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** `say` mode: the briefing twice (Indian English), one second apart. */
export function sayTwiml(text) {
  const t = esc(String(text).slice(0, VOICE_MAX));
  return `<Response><Say language="en-IN">${t}</Say><Pause length="1"/><Say language="en-IN">${t}</Say></Response>`;
}

/** `relay` mode: Twilio ConversationRelay streams speech to our WebSocket and speaks our text back. */
export function relayTwiml(wsUrl, greeting) {
  return `<Response><Connect><ConversationRelay url="${esc(wsUrl)}" language="en-IN" welcomeGreeting="${esc(String(greeting).slice(0, VOICE_MAX))}"/></Connect></Response>`;
}

/** wss URL for a call, or null when PUBLIC_BASE_URL is not public https (Twilio cannot reach localhost). */
export function relayUrl(publicBaseUrl, callId, token) {
  let u;
  try {
    u = new URL(publicBaseUrl);
  } catch {
    return null;
  }
  if (u.protocol !== 'https:' || ['localhost', '127.0.0.1', '0.0.0.0'].includes(u.hostname) || /^(10|192\.168|172\.(1[6-9]|2\d|3[01]))\./.test(u.hostname)) return null;
  return `wss://${u.host}/voice/relay?callId=${encodeURIComponent(callId)}&token=${encodeURIComponent(token)}`;
}

/** Status callback URL, or null when Twilio could not reach it. */
export function statusUrl(publicBaseUrl, callId) {
  const ws = relayUrl(publicBaseUrl, callId, 'x');
  if (!ws) return null;
  return `${new URL(publicBaseUrl).origin}/api/voice/status?callId=${encodeURIComponent(callId)}`;
}

/** The facts the agent may speak about, as short lines. Only real values; unknown things are left out, never guessed. */
export function packetLines(p) {
  const lines = [`Caller: ${p.caller.name}, ${p.caller.role}${p.caller.zoneCode ? `, zone ${p.caller.zoneCode}` : ''}${p.caller.employeeId ? ` (${p.caller.employeeId})` : ''}.`];
  if (p.reason) lines.push(`Reason given: ${p.reason}.`);
  if (p.position) {
    const where = [p.position.tunnelId && `tunnel ${p.position.tunnelId}`, p.position.junction && `near junction ${p.position.junction}`].filter(Boolean).join(', ');
    lines.push(`Last position: ${where || 'known on the map'}, accuracy about ${Math.round(p.position.accuracyM ?? 0)} metres, ${p.position.ageSec <= 60 ? 'live' : `${Math.round(p.position.ageSec / 60)} minutes ago`}.`);
  }
  if (p.sos) lines.push(`The caller has an ACTIVE SOS raised ${Math.max(1, Math.round(p.sos.ageSec / 60))} minutes ago.`);
  if (p.crisis) lines.push(`A mine crisis is ACTIVE${p.crisis.zoneCodes?.length ? ` in ${p.crisis.zoneCodes.join(', ')}` : ''}${p.crisis.reason ? `: ${p.crisis.reason}` : ''}.`);
  if (p.hazards?.count) lines.push(`Open hazards in the caller's zone: ${p.hazards.count} (${p.hazards.categories.join(', ')}).`);
  return lines;
}

/** The fixed briefing used when Gemini is not configured or fails. ≤ 450 chars. */
export function templateBriefing(p, targetLabel) {
  const first = `This is Mine Guardian calling ${targetLabel} on behalf of ${p.caller.name}, ${p.caller.role}${p.caller.zoneCode ? ` in zone ${p.caller.zoneCode}` : ''}.`;
  const rest = packetLines(p).slice(1).join(' ');
  const tail = p.sos || p.crisis ? ' Please respond now.' : ' Please call them back.';
  return `${first} ${rest}${tail}`.replace(/\s+/g, ' ').trim().slice(0, VOICE_MAX);
}
