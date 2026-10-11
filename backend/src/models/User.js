import mongoose from 'mongoose';
import { ROLE, USER_STATUS, SHIFT } from '../contracts/enums.js';
import { applyCommon } from './_plugin.js';

const { Schema } = mongoose;

const userSchema = new Schema(
  {
    firebaseUid: { type: String, required: true, unique: true },
    role: { type: String, enum: ROLE, required: true },
    status: { type: String, enum: USER_STATUS, default: 'active' },
    fullName: { type: String, required: true, trim: true },
    employeeId: { type: String, required: true, unique: true, uppercase: true, trim: true },
    // The Firebase login email: the identity. Login codes are sent here.
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    // Optional contact number (SOS calls/SMS to supervisors). Not an identity, not collected at sign-up, not unique.
    phone: { e164: String },
    designation: String,
    experienceYears: Number,
    dateOfJoining: Date,
    dob: Date,
    bloodGroup: String,
    mineName: String,
    zoneId: {
      type: Schema.Types.ObjectId,
      ref: 'Zone',
      required: function req() {
        return this.role === 'miner' || this.role === 'supervisor';
      },
    },
    shift: { type: String, enum: SHIFT },
    emergencyContact: { name: String, relation: String, e164: String },
    address: String,
    fcmTokens: { type: [String], default: [] },
    lastLoginAt: Date,
  },
  { timestamps: true, collection: 'users' },
);

userSchema.methods.toPublic = function toPublic() {
  const o = this.toJSON();
  delete o.fcmTokens;
  return o;
};

applyCommon(userSchema);
export const User = mongoose.models.User || mongoose.model('User', userSchema);
