// Saves the mine layout and zones to Mongo (no Firebase needed):  npm run seed:layout
import { env } from '../src/config/env.js';
import { connectDb, disconnectDb } from '../src/core/db.js';
import { Zone } from '../src/models/Zone.js';
import { MineLayout } from '../src/models/MineLayout.js';
import { seedLayoutAndZones } from './layout_seed.js';

await connectDb(env.MONGODB_URI);
await Promise.all([Zone.init(), MineLayout.init()]);
const { geojson, zones } = await seedLayoutAndZones();
console.log(`Layout v1 saved (${geojson.features.length} features), zones: ${Object.keys(zones).join(', ')}`);
await disconnectDb();
