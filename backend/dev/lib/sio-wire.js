// Minimal Socket.IO v4 client over a raw WebSocket (the `ws` package), for dev smoke tests only.
// `socket.io-client` must not be a backend dependency (P2.13), so this speaks the wire protocol directly:
// engine.io open "0{...}", ping "2" -> pong "3", namespace connect "40{auth}", event "42[...]", ack "42<id>[...]" -> "43<id>[...]".
import WebSocket from 'ws';

export function connectSio(base, auth, { timeoutMs = 8000 } = {}) {
  const url = `${base.replace(/^http/, 'ws')}/socket.io/?EIO=4&transport=websocket`;
  const ws = new WebSocket(url);
  const events = [];
  const waiters = [];
  const acks = new Map();
  let ackId = 0;

  const deliver = (name, data) => {
    events.push({ name, data, at: Date.now() });
    for (const w of [...waiters]) {
      if (w.name === name && w.match(data)) {
        waiters.splice(waiters.indexOf(w), 1);
        clearTimeout(w.timer);
        w.resolve(data);
      }
    }
  };

  const ready = new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('socket connect timeout')), timeoutMs);
    ws.on('error', (e) => reject(e));
    ws.on('message', (buf) => {
      const msg = buf.toString();
      if (msg.startsWith('0')) ws.send(`40${JSON.stringify(auth)}`);
      else if (msg === '2') ws.send('3');
      else if (msg.startsWith('40')) {
        clearTimeout(t);
        resolve();
      } else if (msg.startsWith('44')) {
        clearTimeout(t);
        reject(new Error(`socket rejected: ${msg.slice(2)}`));
      } else if (msg.startsWith('43')) {
        const m = msg.match(/^43(\d+)(.*)$/s);
        const cb = m && acks.get(Number(m[1]));
        if (cb) {
          acks.delete(Number(m[1]));
          cb(JSON.parse(m[2])[0]);
        }
      } else if (msg.startsWith('42')) {
        const arr = JSON.parse(msg.slice(msg.indexOf('[')));
        deliver(arr[0], arr[1]);
      }
    });
  });

  return {
    ready,
    events,
    /** Resolves with the envelope of the next `name` event whose envelope passes `match`. */
    waitFor(name, match = () => true, ms = timeoutMs) {
      const hit = events.find((e) => e.name === name && match(e.data));
      if (hit) return Promise.resolve(hit.data);
      return new Promise((resolve, reject) => {
        const w = { name, match, resolve, timer: setTimeout(() => reject(new Error(`no ${name} within ${ms} ms`)), ms) };
        waiters.push(w);
      });
    },
    /** Emits with an ack; resolves with the server's ack payload. */
    emit(name, data, ms = timeoutMs) {
      ackId += 1;
      const id = ackId;
      return new Promise((resolve, reject) => {
        const t = setTimeout(() => reject(new Error(`no ack for ${name}`)), ms);
        acks.set(id, (v) => {
          clearTimeout(t);
          resolve(v);
        });
        ws.send(`42${id}${JSON.stringify([name, data])}`);
      });
    },
    clear() {
      events.length = 0;
    },
    close() {
      ws.close();
    },
  };
}
