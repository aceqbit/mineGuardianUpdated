// Creates an OPEN hazard in Mongo with a photo in Storage, then posts HazardCreated so the AI classifies it.
// Usage: node dev/phase2/fake-hazard.js --email you+min-0105@gmail.com --category FIRE_SMOKE --image <path>
import crypto from 'node:crypto';
import fs from 'node:fs';
import { connectMongo, bus } from '../lib/common.js';
import { argv, pickInsideZone, loadModels } from './_util.js';

const email = argv('email');
const image = argv('image');
const category = argv('category', 'OTHER');
if (!email || !image || !fs.existsSync(image)) {
  console.error('Usage: node dev/phase2/fake-hazard.js --email you+min-0105@gmail.com --category FIRE_SMOKE --image <path>');
  process.exit(1);
}

const mongoose = await connectMongo();
try {
  const { User, Zone, Hazard, uploadBuffer } = await loadModels();
  const reporter = await User.findOne({ email: String(email).toLowerCase() });
  if (!reporter) throw new Error('reporter not found');
  const zone = await Zone.findById(reporter.zoneId);
  const id = new mongoose.Types.ObjectId();
  const storagePath = `hazards/${zone._id}/${id}.jpg`;
  await uploadBuffer(storagePath, fs.readFileSync(image));
  const pt = pickInsideZone(zone);
  await Hazard.create({
    _id: id, clientId: crypto.randomUUID(), reporterId: reporter._id, zoneId: zone._id, category, storagePath,
    location: { type: 'Point', coordinates: [pt.lng, pt.lat] }, accuracyM: 8, capturedAt: new Date(Date.now() - 15000), receivedAt: new Date(), status: 'OPEN',
  });
  await bus('HazardCreated', { hazardId: String(id) });
  console.log(`hazard ${id} (${category}) created; HazardCreated published`);
} finally {
  await mongoose.disconnect();
}
