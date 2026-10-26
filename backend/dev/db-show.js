// Dev tool: read-only view of what is stored in MongoDB (the database named by backend/.env).
// Never writes. Emails, phone numbers, tokens and hashes are masked unless --full is passed.
// Usage (from backend/):
//   node dev/db-show.js                       every collection with its record count
//   node dev/db-show.js users                 the newest 10 records of one collection
//   node dev/db-show.js users --limit 50      more records
//   node dev/db-show.js --all                 the newest 5 records of every collection
//   node dev/db-show.js users --full          without masking (do not project this)
import 'dotenv/config';
import mongoose from 'mongoose';
import { connectDb } from '../src/core/db.js';
import { maskPhone } from '../src/core/logger.js';

if (!process.env.MONGODB_URI) {
  console.error('MONGODB_URI is not set (backend/.env)');
  process.exit(1);
}

const args = process.argv.slice(2);
const full = args.includes('--full');
const all = args.includes('--all');
const limitIdx = args.indexOf('--limit');
const limit = limitIdx >= 0 ? Number(args[limitIdx + 1]) || 10 : all ? 5 : 10;
const name = args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--limit');

const SECRET_KEYS = /token|hash|password|secret|codeHash|shareToken/i;

function maskEmail(s) {
  const [user, domain] = s.split('@');
  return `${user.slice(0, 1)}***@${domain}`;
}

// Masks personal data and secrets, shortens long arrays (polygons, layout GeoJSON) so a record fits on screen.
function clean(v, key = '') {
  if (v === null || v === undefined) return v;
  if (v instanceof Date) return v.toISOString();
  if (v instanceof mongoose.Types.ObjectId || v?._bsontype === 'ObjectId') return String(v);
  if (Buffer.isBuffer(v) || v?._bsontype === 'Binary') return '<binary>';
  if (Array.isArray(v)) {
    if (key === 'coordinates' || v.length > 8) return `[${v.length} items]`;
    return v.map((x) => clean(x, key));
  }
  if (typeof v === 'object') {
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = clean(x, k);
    return out;
  }
  if (typeof v === 'string' && !full) {
    if (SECRET_KEYS.test(key)) return '<hidden>';
    if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) return maskEmail(v);
    if (/^\+\d{8,15}$/.test(v)) return maskPhone(v);
    if (v.startsWith('http') && v.length > 80) return `${v.slice(0, 60)}…`;
  }
  return v;
}

await connectDb(process.env.MONGODB_URI);
const db = mongoose.connection.db;
console.log(`Database: ${db.databaseName}\n`);

const collections = (await db.listCollections().toArray()).map((c) => c.name).sort();

if (!name && !all) {
  const rows = [];
  for (const c of collections) rows.push({ collection: c, records: await db.collection(c).countDocuments() });
  console.table(rows);
  console.log(`Total records: ${rows.reduce((s, r) => s + r.records, 0)} in ${rows.length} collections`);
  console.log('Show one collection: node dev/db-show.js <collection>   |   all: node dev/db-show.js --all');
} else {
  const targets = all ? collections : [name];
  for (const c of targets) {
    if (!collections.includes(c)) {
      console.error(`No collection "${c}". Existing: ${collections.join(', ')}`);
      process.exitCode = 1;
      continue;
    }
    const total = await db.collection(c).countDocuments();
    const docs = await db.collection(c).find().sort({ _id: -1 }).limit(limit).toArray();
    console.log(`=== ${c}: ${total} records (showing newest ${docs.length}) ===`);
    for (const d of docs) console.dir(clean(d), { depth: 4, colors: process.stdout.isTTY });
    console.log('');
  }
}

await mongoose.disconnect();
