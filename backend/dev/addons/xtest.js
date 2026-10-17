// Throwaway test database for the add-on pack (never the real one): same cluster, database MONGODB_DB=mineguardian_xtest.
//   node dev/addons/xtest.js fixture   -> resets mineguardian_xtest and prints the fixture ids as JSON
//   node dev/addons/xtest.js server    -> runs the API on PORT (default 4100) against mineguardian_xtest
//   node dev/addons/xtest.js drop      -> drops mineguardian_xtest
import 'dotenv/config';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const XTEST_DB = 'mineguardian_xtest';


const here = path.dirname(fileURLToPath(import.meta.url));
const backend = path.join(here, '..', '..');

async function connect() {
  process.env.MONGODB_DB = XTEST_DB;
  const { default: mongoose } = await import('mongoose');
  await mongoose.connect(process.env.MONGODB_URI, { dbName: XTEST_DB, serverSelectionTimeoutMS: 8000 });
  if (mongoose.connection.name !== XTEST_DB) throw new Error(`refusing to touch database ${mongoose.connection.name}`);
  return mongoose;
}

const square = (x0, x1) => [[[x0, 23.74], [x1, 23.74], [x1, 23.75], [x0, 23.75], [x0, 23.74]]];

export async function fixture() {
  const mongoose = await connect();
  await mongoose.connection.db.dropDatabase();
  const { Zone } = await import('../../src/models/Zone.js');
  const { User } = await import('../../src/models/User.js');
  const { CheckIn } = await import('../../src/models/CheckIn.js');
  const { Hazard } = await import('../../src/models/Hazard.js');
  const base = { mineName: 'XTest Colliery', requiredPpe: ['HELMET', 'REFLECTIVE_VEST', 'SAFETY_BOOTS', 'GLOVES'] };
  const za = await Zone.create({ ...base, code: 'XT-A', name: 'Test West', polygon: { type: 'Polygon', coordinates: square(86.41, 86.414) } });
  const zb = await Zone.create({ ...base, code: 'XT-B', name: 'Test East', polygon: { type: 'Polygon', coordinates: square(86.414, 86.418) } });
  const mk = (role, emp, zone, extra = {}) => User.create({ firebaseUid: `xt-${emp}`, role, fullName: `XT ${emp}`, employeeId: emp, email: `xt+${emp.toLowerCase()}@example.com`, zoneId: zone?._id, shift: role === 'admin' ? undefined : 'A', ...extra });
  const admin = await mk('admin', 'XADM-1', null);
  const supA = await mk('supervisor', 'XSUP-A', za, { phone: { e164: '+919876500011' } });
  const supB = await mk('supervisor', 'XSUP-B', zb);
  const minersA = [];
  for (let i = 1; i <= 3; i += 1) minersA.push(await mk('miner', `XMIN-A${i}`, za, { phone: { e164: `+9198765001${10 + i}` }, bloodGroup: 'O+', medicalNotes: 'test note' }));
  // A deliberately unsafe number: proves the emergency blocklist fires through every dialling route.
  const minerB = await mk('miner', 'XMIN-B1', zb, { phone: { e164: '+91112' } });
  za.supervisorIds = [supA._id];
  zb.supervisorIds = [supB._id];
  await za.save();
  await zb.save();
  const ci = await CheckIn.create({ workerId: minersA[0]._id, zoneId: za._id, clientId: `xt-ci-${Date.now()}`, storagePath: 'checkins/xt/none.jpg', status: 'PREDICTED', capturedAt: new Date(), location: { type: 'Point', coordinates: [86.412, 23.745] } });
  await mongoose.connection.collection('compliance_reviews').insertOne({ checkInId: ci._id, workerId: minersA[0]._id, zoneId: za._id, status: 'PENDING_REVIEW', ai: { overallVerdict: 'NON_COMPLIANT' }, createdAt: new Date() });
  const day = new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
  await mongoose.connection.collection('score_snapshots').insertMany(minersA.map((m, i) => ({ userId: m._id, zoneId: za._id, day, score: 800 - i * 100, streak: 3 - i, xp: 50, badges: [], riskBand: i === 2 ? 'RED' : 'GREEN' })));
  await Hazard.create({ reporterId: minersA[0]._id, zoneId: za._id, clientId: `xt-hz-${Date.now()}`, category: 'ROOF_FALL', storagePath: 'hazards/xt/none.jpg', location: { type: 'Point', coordinates: [86.412, 23.745] } });
  const ids = { zoneA: String(za._id), zoneB: String(zb._id), admin: String(admin._id), supA: String(supA._id), supB: String(supB._id), minersA: minersA.map((m) => String(m._id)), minerB: String(minerB._id), checkIn: String(ci._id) };
  await mongoose.disconnect();
  return ids;
}

export async function drop() {
  const mongoose = await connect();
  await mongoose.connection.db.dropDatabase();
  await mongoose.disconnect();
}

/** Starts the API against the test DB with the dev bypass on. Returns the child process. */
export function server(port = process.env.PORT || 4100) {
  return spawn(process.execPath, ['src/server.js'], {
    cwd: backend,
    env: { ...process.env, MONGODB_DB: XTEST_DB, PORT: String(port), NODE_ENV: 'development', DEV_AUTH_BYPASS: 'true', STORAGE_DRIVER: 'local', TWILIO_DRY_RUN: 'true', VOICE_AGENT_MODE: 'say', ...(process.env.XTEST_LIVE_AI === '1' ? {} : { GEMINI_API_KEY: '' }) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const cmd = process.argv[2];
  if (cmd === 'fixture') console.log(JSON.stringify(await fixture(), null, 2));
  else if (cmd === 'drop') {
    await drop();
    console.log(`dropped ${XTEST_DB}`);
  } else if (cmd === 'server') {
    const child = server();
    child.stdout.pipe(process.stdout);
    child.stderr.pipe(process.stderr);
  } else {
    console.log('usage: node dev/addons/xtest.js fixture|server|drop');
  }
}
