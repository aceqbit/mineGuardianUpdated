// Creates an ACTIVE SosEvent in Mongo and posts SosTriggered (the crisis orchestrator picks it up).
// Usage: node dev/phase2/fake-sos.js --email you+min-0105@gmail.com
import crypto from 'node:crypto';
import { connectMongo, bus } from '../lib/common.js';
import { argv, pickInsideZone, loadModels } from './_util.js';

const email = argv('email');
if (!email) {
  console.error('Usage: node dev/phase2/fake-sos.js --email you+min-0105@gmail.com');
  process.exit(1);
}

const mongoose = await connectMongo();
try {
  const { User, Zone, SosEvent } = await loadModels();
  const worker = await User.findOne({ email: String(email).toLowerCase() });
  if (!worker) throw new Error('worker not found');
  const zone = await Zone.findById(worker.zoneId);
  const pt = pickInsideZone(zone);
  const sos = await SosEvent.create({
    clientId: crypto.randomUUID(), workerId: worker._id, zoneId: zone._id, location: { type: 'Point', coordinates: [pt.lng, pt.lat] }, accuracyM: 8,
    triggeredAt: new Date(), receivedAt: new Date(), status: 'ACTIVE',
  });
  await bus('SosTriggered', { sosId: String(sos._id) });
  console.log(`SOS ${sos._id} created for ${worker.fullName}; SosTriggered published`);
} finally {
  await mongoose.disconnect();
}
