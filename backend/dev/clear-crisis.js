// Dev tool: closes any leftover ACTIVE crisis and cancels leftover ACTIVE SOS events in the database named by backend/.env.
// Smoke tests and simulators can leave these behind, which makes every phone show "EVACUATE" at start-up.
// Usage (from backend/):  node dev/clear-crisis.js
import 'dotenv/config';
import mongoose from 'mongoose';
import { connectDb } from '../src/core/db.js';

if (process.env.NODE_ENV === 'production') {
  console.error('Refusing to run with NODE_ENV=production');
  process.exit(1);
}
if (!process.env.MONGODB_URI) {
  console.error('MONGODB_URI is not set (backend/.env)');
  process.exit(1);
}

await connectDb(process.env.MONGODB_URI); // same database name as the server (MONGODB_DB, default mine_guardian)
const db = mongoose.connection;
const now = new Date();
const crises = await db.collection('crises').updateMany({ status: 'ACTIVE' }, { $set: { status: 'RESOLVED', falseAlarm: true, resolvedAt: now, resolveNote: 'Cleared by dev/clear-crisis.js' } });
const sos = await db.collection('sos_events').updateMany({ status: 'ACTIVE' }, { $set: { status: 'CANCELLED', cancelledAt: now } });
console.log(`Crises closed: ${crises.modifiedCount}. SOS events cancelled: ${sos.modifiedCount}.`);
await mongoose.disconnect();
