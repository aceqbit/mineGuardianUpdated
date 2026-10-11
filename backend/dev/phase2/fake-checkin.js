// Creates a RECEIVED check-in directly in Mongo (realistic timestamps, location inside the zone), uploads the photo to Storage,
// then posts CheckInCreated to /dev/bus so the AI pipeline picks it up.
// Usage: node dev/phase2/fake-checkin.js --email you+min-0105@gmail.com --image src/modules/ai-analyzer/eval/images/c01.jpg [--source camera|gallery]
import crypto from 'node:crypto';
import fs from 'node:fs';
import { connectMongo, bus } from '../lib/common.js';
import { argv, pickInsideZone, loadModels } from './_util.js';

const email = argv('email');
const image = argv('image');
if (!email || !image || !fs.existsSync(image)) {
  console.error('Usage: node dev/phase2/fake-checkin.js --email you+min-0105@gmail.com --image <path> [--source camera|gallery]');
  process.exit(1);
}

const mongoose = await connectMongo();
try {
  const { User, Zone, CheckIn, uploadBuffer } = await loadModels();
  const worker = await User.findOne({ email: String(email).toLowerCase() });
  if (!worker) throw new Error('worker not found');
  const zone = await Zone.findById(worker.zoneId);
  const buf = fs.readFileSync(image);
  const id = new mongoose.Types.ObjectId();
  const now = new Date();
  const ist = new Date(now.getTime() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);
  const storagePath = `checkins/${worker._id}/${ist}/${id}.jpg`;
  await uploadBuffer(storagePath, buf);
  const pt = pickInsideZone(zone);
  const capturedAt = new Date(now.getTime() - 20 * 1000);
  await CheckIn.create({
    _id: id, workerId: worker._id, zoneId: zone._id, shift: worker.shift, clientId: crypto.randomUUID(), storagePath, source: argv('source', 'camera'), attempt: 1,
    capturedAt, uploadStartedAt: new Date(now.getTime() - 5000), receivedAt: now, clockSkewSec: 0,
    location: { type: 'Point', coordinates: [pt.lng, pt.lat] }, accuracyM: 8, insideZone: true, withinShift: true,
    clientQuality: { blurScore: 120, brightness: 130, width: 1200, height: 1600, poseChecked: true, poseOk: true, missingLandmarks: [] },
    serverQuality: { blurScore: 90, brightness: 128, width: 1200, height: 1600, pass: true }, sha256: crypto.createHash('sha256').update(buf).digest('hex'), integrityFlags: [], status: 'RECEIVED',
  });
  await bus('CheckInCreated', { checkInId: String(id) });
  console.log(`check-in ${id} created for ${worker.fullName}; CheckInCreated published`);
} finally {
  await mongoose.disconnect();
}
