import mongoose from 'mongoose';
import { PPE_KEY, SHIFT } from '../contracts/enums.js';
import { applyCommon } from './_plugin.js';

const { Schema } = mongoose;

const zoneSchema = new Schema(
  {
    code: { type: String, required: true, unique: true },
    name: { type: String, required: true },
    mineName: { type: String, required: true },
    polygon: {
      type: { type: String, enum: ['Polygon'], default: 'Polygon' },
      coordinates: { type: [[[Number]]], required: true },
    },
    supervisorIds: [{ type: Schema.Types.ObjectId, ref: 'User' }],
    requiredPpe: [{ type: String, enum: PPE_KEY }],
    shiftWindows: [{ _id: false, shift: { type: String, enum: SHIFT }, start: String, end: String }],
    // Layout exit id the admin designated as this zone's emergency exit (null = nearest safe exit, decided on the phone).
    evacExitId: { type: String, default: null },
  },
  { timestamps: true, collection: 'zones' },
);
zoneSchema.index({ polygon: '2dsphere' });
applyCommon(zoneSchema);
export const Zone = mongoose.models.Zone || mongoose.model('Zone', zoneSchema);
