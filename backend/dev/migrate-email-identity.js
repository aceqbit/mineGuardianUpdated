// One-time: moves an existing database from phone logins to email logins. Safe to run twice.
// Drops the old unique indexes (phone.e164, loginEmail), removes loginEmail from every user and lists users that still have no email.
// Usage (from backend/):  node dev/migrate-email-identity.js
import { env } from '../src/config/env.js';
import { connectDb, disconnectDb } from '../src/core/db.js';
import { User } from '../src/models/User.js';

if (env.NODE_ENV === 'production') {
  console.error('Refusing to run with NODE_ENV=production');
  process.exit(1);
}
await connectDb(env.MONGODB_URI);
for (const name of ['phone.e164_1', 'loginEmail_1']) {
  try {
    await User.collection.dropIndex(name);
    console.log(`dropped index ${name}`);
  } catch {
    /* already gone */
  }
}
const r = await User.collection.updateMany({}, { $unset: { loginEmail: '' } });
console.log(`loginEmail removed from ${r.modifiedCount} users`);
const noEmail = await User.find({ $or: [{ email: null }, { email: '' }, { email: { $exists: false } }] }).select('employeeId role');
if (noEmail.length) console.log('Users without an email (re-create them with the seed or sign-up):', noEmail.map((u) => u.employeeId).join(', '));
await User.syncIndexes();
await disconnectDb();
