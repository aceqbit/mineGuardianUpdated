// Dev tool: creates (or re-links) one sample miner in zone Z-B with an email login. Idempotent. Needs no service account.
// Usage (from backend/, after `npm run seed:layout`):  node dev/create-sample-user.js you@gmail.com '<6-char password>'
import { env } from '../src/config/env.js';
import { connectDb, disconnectDb } from '../src/core/db.js';
import { User } from '../src/models/User.js';
import { Zone } from '../src/models/Zone.js';
import { ensureIdentity } from '../seed/identity.js';

if (env.NODE_ENV === 'production') {
  console.error('Refusing to run with NODE_ENV=production');
  process.exit(1);
}
const email = (process.argv[2] || '').trim().toLowerCase();
const password = process.argv[3] || '';
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || password.length !== 6) {
  console.error("Usage: node dev/create-sample-user.js you@gmail.com '<exactly 6 characters, a letter and a digit>'");
  process.exit(1);
}

const uid = await ensureIdentity(email, password); // fails if the login exists with another password

await connectDb(env.MONGODB_URI);
const zone = await Zone.findOne({ code: 'Z-B' });
if (!zone) {
  console.error('Zone Z-B not found. Run `npm run seed:layout` first.');
  process.exit(1);
}
await User.findOneAndUpdate(
  { employeeId: 'MIN-0199' },
  {
    $set: {
      firebaseUid: uid, email, role: 'miner', status: 'active', fullName: 'Sample Miner', employeeId: 'MIN-0199',
      designation: 'Miner', experienceYears: 4, dateOfJoining: new Date(2022, 0, 5), dob: new Date(1994, 4, 10),
      bloodGroup: 'O+', mineName: zone.mineName, zoneId: zone._id, shift: 'A',
    },
    $unset: { phone: '', loginEmail: '', emergencyContact: '' },
  },
  { upsert: true, new: true, setDefaultsOnInsert: true },
);
console.log(`Sample miner ready: ${email.replace(/^(.).*@/, '$1***@')}, zone Z-B, employee MIN-0199`);
await disconnectDb();
