import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import WebSocket from 'ws';
import { canCall, isFinal, packetLines, relayTwiml, relayUrl, sayTwiml, statusFromTwilio, statusUrl, takeCooldown, templateBriefing, VOICE_MAX } from '../src/modules/voice/voice.logic.js';
import { attachRelay, RELAY_PATH } from '../src/modules/voice/relay.js';
import { assertSafeDialTarget } from '../src/modules/contacts/contacts.logic.js';

const u = (id, role, zoneId) => ({ _id: id, role, zoneId });
const minerA = u('m1', 'miner', 'ZA');
const minerA2 = u('m2', 'miner', 'ZA');
const supA = u('s1', 'supervisor', 'ZA');
const supB = u('s2', 'supervisor', 'ZB');
const admin = u('a1', 'admin');

test('who may call whom', () => {
  assert.equal(canCall(minerA, 'user', supA), true, 'miner -> own supervisor');
  assert.equal(canCall(minerA, 'user', admin), true, 'miner -> admin');
  assert.equal(canCall(minerA, 'user', supB), false, 'miner -> other zone supervisor');
  assert.equal(canCall(minerA, 'user', minerA2), false, 'miner -> miner');
  assert.equal(canCall(minerA, 'contact', {}), false, 'miner -> emergency contact');
  assert.equal(canCall(supA, 'user', minerA), true);
  assert.equal(canCall(supA, 'user', u('m9', 'miner', 'ZB')), false);
  assert.equal(canCall(supA, 'contact', {}), true);
  assert.equal(canCall(admin, 'user', u('m9', 'miner', 'ZB')), true);
  assert.equal(canCall(admin, 'user', admin), false, 'never yourself');
});

test('the emergency blocklist still guards every AI call', () => {
  for (const n of ['+91112', '+91100', '+911078', '+1911', '+44999', '12345']) assert.throws(() => assertSafeDialTarget(n), /UNSAFE|valid|Short|emergency/i, n);
  assert.equal(assertSafeDialTarget('+919876500101'), true);
});

test('cooldown: one call per caller and target every 30 s', () => {
  const book = new Map();
  assert.equal(takeCooldown(book, 'a', 'b', 1000), 0);
  assert.equal(takeCooldown(book, 'a', 'b', 11_000), 20);
  assert.equal(takeCooldown(book, 'a', 'c', 11_000), 0, 'another target is fine');
  assert.equal(takeCooldown(book, 'a', 'b', 31_001), 0);
});

test('Twilio status mapping', () => {
  assert.equal(statusFromTwilio('ringing'), 'RINGING');
  assert.equal(statusFromTwilio('in-progress'), 'IN_PROGRESS');
  assert.equal(statusFromTwilio('completed'), 'COMPLETED');
  for (const s of ['busy', 'no-answer', 'failed', 'canceled']) assert.equal(statusFromTwilio(s), 'FAILED');
  assert.equal(statusFromTwilio('weird'), null);
  assert.ok(isFinal('DRY_RUN') && !isFinal('RINGING'));
});

test('TwiML: escaped, spoken twice in en-IN, capped at 450 chars', () => {
  const t = sayTwiml(`<Hello> & "x" ${'a'.repeat(600)}`);
  assert.match(t, /^<Response><Say language="en-IN">&lt;Hello&gt; &amp; &quot;x&quot;/);
  assert.equal((t.match(/<Say /g) || []).length, 2);
  assert.ok(t.length < 2 * VOICE_MAX + 200);
  const r = relayTwiml('wss://x.example/voice/relay?callId=1&token=a"b', 'Hi "there"');
  assert.match(r, /<Connect><ConversationRelay url="wss:\/\/x\.example\/voice\/relay\?callId=1&amp;token=a&quot;b" language="en-IN" welcomeGreeting="Hi &quot;there&quot;"\/><\/Connect>/);
});

test('relay and status URLs only for a public https base (Twilio cannot reach localhost)', () => {
  assert.equal(relayUrl('http://localhost:4000', 'c1', 't'), null);
  assert.equal(relayUrl('https://localhost', 'c1', 't'), null);
  assert.equal(relayUrl('https://192.168.1.20', 'c1', 't'), null);
  assert.equal(relayUrl('http://mine.example.com', 'c1', 't'), null);
  assert.equal(relayUrl('https://mine.example.com', 'c1', 't k'), 'wss://mine.example.com/voice/relay?callId=c1&token=t%20k');
  assert.equal(statusUrl('https://mine.example.com/', 'c1'), 'https://mine.example.com/api/voice/status?callId=c1');
  assert.equal(statusUrl('http://127.0.0.1:4000', 'c1'), null);
});

test('briefing template: only real facts, no undefined/null, <= 450 chars', () => {
  const quiet = templateBriefing({ caller: { name: 'Ravi Kumar', role: 'miner', zoneCode: 'Z-B', employeeId: 'MIN-0105' } }, 'Sunil (supervisor)');
  assert.match(quiet, /^This is Mine Guardian calling Sunil \(supervisor\) on behalf of Ravi Kumar, miner in zone Z-B\./);
  assert.match(quiet, /call them back\.$/);
  const busy = templateBriefing({
    caller: { name: 'Ravi', role: 'miner', zoneCode: 'Z-B' }, reason: 'roof noise',
    position: { tunnelId: 'T-J4-J5', junction: 'J5', accuracyM: 6.4, ageSec: 10 }, sos: { ageSec: 120 }, crisis: { zoneCodes: ['Z-B'], reason: 'SOS' },
    hazards: { count: 2, categories: ['roof fall', 'gas leak'] },
  }, 'Control room');
  assert.match(busy, /tunnel T-J4-J5, near junction J5/);
  assert.match(busy, /ACTIVE SOS/);
  assert.match(busy, /respond now\.$/);
  assert.ok(busy.length <= VOICE_MAX);
  for (const s of [quiet, busy]) assert.doesNotMatch(s, /undefined|null|NaN/);
  assert.equal(packetLines({ caller: { name: 'X', role: 'admin' } }).length, 1);
});

function relayServer({ authorize, reply }) {
  const server = http.createServer();
  const statuses = [];
  attachRelay(server, { authorize, reply, onStatus: (_s, st) => statuses.push(st), maxSec: 30 });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port, statuses })));
}

test('relay: authorised call streams the reply tokens and a final last:true', async () => {
  const { server, port, statuses } = await relayServer({
    authorize: async (callId, token) => (callId === 'c1' && token === 'good' ? { callId, packet: {}, turns: 0 } : null),
    reply: async (_s, history, text, onToken) => {
      onToken('You said ');
      onToken(text);
      return `You said ${text}`;
    },
  });
  const ws = new WebSocket(`ws://127.0.0.1:${port}${RELAY_PATH}?callId=c1&token=good`);
  const got = [];
  await new Promise((resolve, reject) => {
    ws.on('open', () => {
      ws.send(JSON.stringify({ type: 'setup', callSid: 'CA1' }));
      ws.send(JSON.stringify({ type: 'prompt', voicePrompt: 'where is Ravi', last: true }));
    });
    ws.on('message', (b) => {
      const m = JSON.parse(b.toString());
      got.push(m);
      if (m.type === 'text' && m.last === true) resolve();
    });
    ws.on('error', reject);
    setTimeout(() => reject(new Error('no reply')), 3000);
  });
  ws.close();
  await new Promise((r) => setTimeout(r, 100));
  server.close();
  assert.deepEqual(got.filter((m) => m.last === false).map((m) => m.token), ['You said ', 'where is Ravi']);
  assert.deepEqual(statuses, ['IN_PROGRESS', 'COMPLETED']);
});

test('relay: a wrong token is refused with 401 before any WebSocket opens', async () => {
  const { server, port } = await relayServer({ authorize: async () => null, reply: async () => '' });
  const err = await new Promise((resolve) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}${RELAY_PATH}?callId=c1&token=bad`);
    ws.on('unexpected-response', (_req, res) => resolve(res.statusCode));
    ws.on('error', () => resolve('error'));
    ws.on('open', () => resolve('opened'));
  });
  server.close();
  assert.ok(err === 401 || err === 'error', `got ${err}`);
});

test('agent reply without a Gemini key streams the safe fallback line (never silence)', async () => {
  const { reply } = await import('../src/modules/voice/agent.js');
  const tokens = [];
  const full = await reply({ caller: { name: 'X', role: 'miner' } }, [], 'hello', (t) => tokens.push(t));
  if (process.env.GEMINI_API_KEY) return; // a configured key makes this a live call; the fallback path is what is pinned here
  assert.match(full, /cannot answer that right now/);
  assert.equal(tokens.join(''), full);
});
