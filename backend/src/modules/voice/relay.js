// Twilio ConversationRelay WebSocket (CLAUDE.md section 23.5). Twilio does speech-to-text and text-to-speech; we receive
// `setup` / `prompt` / `interrupt` messages and stream `text` tokens back. Mounted on the API's own HTTP server at
// /voice/relay (socket.io keeps /socket.io). Each call carries a one-time token in the URL; anything else is refused.
import { WebSocketServer } from 'ws';
import { logger } from '../../core/logger.js';
import { MAX_TURNS } from './voice.logic.js';

export const RELAY_PATH = '/voice/relay';

/**
 * attachRelay(httpServer, { authorize(callId, token) -> session|null, reply(session, history, text, onToken) -> full,
 *   onStatus(session, status), maxSec })
 */
export function attachRelay(httpServer, { authorize, reply, onStatus, maxSec = 180 }) {
  const wss = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024 });

  httpServer.on('upgrade', async (req, socket, head) => {
    let url;
    try {
      url = new URL(req.url, 'http://relay.local');
    } catch {
      return;
    }
    if (url.pathname !== RELAY_PATH) return; // not ours (socket.io handles its own path)
    const session = await authorize(url.searchParams.get('callId'), url.searchParams.get('token')).catch(() => null);
    if (!session) {
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => run(ws, session));
  });

  function run(ws, session) {
    const history = [];
    let turns = 0;
    let busy = false;
    let interrupted = false;
    const send = (o) => ws.readyState === ws.OPEN && ws.send(JSON.stringify(o));
    const end = (line) => {
      if (line) send({ type: 'text', token: line, last: true });
      setTimeout(() => send({ type: 'end' }), 1500);
    };
    const timer = setTimeout(() => end('We have reached the time limit for this call. Goodbye.'), maxSec * 1000);

    ws.on('message', async (buf) => {
      let m;
      try {
        m = JSON.parse(buf.toString());
      } catch {
        return;
      }
      if (m.type === 'setup') {
        onStatus(session, 'IN_PROGRESS');
        return;
      }
      if (m.type === 'interrupt') {
        interrupted = true;
        return;
      }
      if (m.type !== 'prompt' || m.last === false || !m.voicePrompt) return;
      if (busy) return; // one reply at a time; Twilio re-prompts if needed
      turns += 1;
      if (turns > MAX_TURNS) return end('I have shared everything I know. Please speak to the caller directly. Goodbye.');
      busy = true;
      interrupted = false;
      try {
        const text = String(m.voicePrompt).slice(0, 600);
        const full = await reply(session, history, text, (token) => {
          if (!interrupted) send({ type: 'text', token, last: false });
        });
        send({ type: 'text', token: '', last: true });
        history.push({ role: 'user', text }, { role: 'model', text: full });
        session.turns = turns;
        if (/\b(bye|goodbye|thank you, bye)\b/i.test(text)) end('Goodbye. Stay safe.');
      } catch (err) {
        logger.warn({ err: err.message }, 'voice relay reply failed');
      } finally {
        busy = false;
      }
    });

    ws.on('close', () => {
      clearTimeout(timer);
      onStatus(session, 'COMPLETED');
    });
    ws.on('error', () => clearTimeout(timer));
  }

  return wss;
}
