// Idempotent seed: zones, layout v1, 16 demo accounts (Firebase email logins + Mongo). `--reset` wipes collections first.
// Needs SEED_EMAIL=you@gmail.com (see seed/accounts.js). No Firebase service account is required.
import { env } from '../src/config/env.js';
import { connectDb, disconnectDb } from '../src/core/db.js';
import { User } from '../src/models/User.js';
import { Zone } from '../src/models/Zone.js';
import { MineLayout } from '../src/models/MineLayout.js';
import { CheckIn } from '../src/models/CheckIn.js';
import { Hazard } from '../src/models/Hazard.js';
import { SosEvent } from '../src/models/SosEvent.js';
import { ComplianceReview } from '../src/models/ComplianceReview.js';
import { AuditLog } from '../src/models/AuditLog.js';
import { seedContacts } from './contacts.js';
import { MINE, ZONES, seedLayoutAndZones } from './layout_seed.js';
import { demoEmailFor } from './accounts.js';
import { ensureIdentity } from './identity.js';

const MINER_NAMES = [
  'Ravi Kumar', 'Suresh Yadav', 'Mohan Singh', 'Anil Mahato', 'Dinesh Oraon', 'Prakash Munda',
  'Rakesh Sharma', 'Santosh Paswan', 'Vijay Thakur', 'Manoj Rajak', 'Arjun Tudu', 'Bikash Ghosh',
];
const SUP_NAMES = ['Ramesh Prasad', 'Sunil Banerjee', 'Ajay Verma'];
const BLOOD = ['A+', 'B+', 'O+', 'AB+', 'O-', 'B-'];

const pad = (n, w = 4) => String(n).padStart(w, '0');

async function main() {
  const reset = process.argv.includes('--reset');
  demoEmailFor('ADM-0001'); // fail early when SEED_EMAIL is missing
  await connectDb(env.MONGODB_URI);
  if (reset) {
    for (const M of [User, Zone, MineLayout, CheckIn, Hazard, SosEvent, ComplianceReview, AuditLog]) await M.deleteMany({});
    console.log('Collections wiped');
  }
  await Promise.all([User.init(), Zone.init(), CheckIn.init(), Hazard.init(), SosEvent.init(), ComplianceReview.init()]);

  const { zones } = await seedLayoutAndZones();

  const people = [];
  people.push({ role: 'admin', name: 'Anita Deshmukh', password: 'Admin1', employeeId: 'ADM-0001', designation: 'Supervisor', zone: null });
  ZONES.forEach((z, i) => people.push({ role: 'supervisor', name: SUP_NAMES[i], password: 'Super1', employeeId: `SUP-${pad(11 + i)}`, designation: 'Mining Sirdar', zone: z.code }));
  MINER_NAMES.forEach((n, i) =>
    people.push({
      role: 'miner', name: n, password: 'Miner1', employeeId: `MIN-${pad(101 + i)}`,
      designation: 'Miner', zone: ZONES[Math.floor(i / 4)].code, shift: i % 2 === 0 ? 'A' : 'B',
    }),
  );

  const table = [];
  for (const [idx, p] of people.entries()) {
    const email = demoEmailFor(p.employeeId);
    const uid = await ensureIdentity(email, p.password);
    const zone = p.zone ? zones[p.zone] : null;
    const doc = {
      firebaseUid: uid, email, role: p.role, status: 'active', fullName: p.name, employeeId: p.employeeId,
      designation: p.designation, experienceYears: 3 + (idx % 12), dateOfJoining: new Date(2018 + (idx % 6), idx % 12, 5),
      dob: new Date(1980 + (idx % 15), idx % 12, 10), bloodGroup: BLOOD[idx % BLOOD.length], mineName: MINE,
      zoneId: zone?._id, shift: p.shift || (p.role === 'supervisor' ? 'A' : undefined),
    };
    const u = await User.findOneAndUpdate({ employeeId: p.employeeId }, { $set: doc }, { upsert: true, new: true, setDefaultsOnInsert: true });
    if (p.role === 'supervisor') await Zone.updateOne({ _id: zone._id }, { $addToSet: { supervisorIds: u._id } });
    table.push({ role: p.role, id: u.id, employeeId: p.employeeId, email: email.replace(/^(.).*?(\+.*)$/, '$1***$2'), zone: p.zone || '-', password: p.password });
  }
  console.table(table);
  console.log(`Emergency contacts: ${await seedContacts()} (dial target = verified team number, never a real emergency number)`);
  console.log(`Seed complete: ${ZONES.length} zones, layout v1, ${people.length} users`);
  await disconnectDb();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
