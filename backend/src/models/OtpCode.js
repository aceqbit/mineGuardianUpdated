import mongoose from 'mongoose';
import { applyCommon } from './_plugin.js';

/** One live email code per Firebase uid. Only a hash of the code is stored; Mongo deletes the row at `expiresAt`. */
const otpCodeSchema = new mongoose.Schema(
  {
    firebaseUid: { type: String, required: true, unique: true },
    target: { type: String, required: true }, // normalised email the code was sent to
    codeHash: { type: String, required: true },
    attempts: { type: Number, default: 0 },
    sentAt: { type: Date, required: true },
    windowStart: { type: Date, required: true },
    sendCount: { type: Number, default: 1 },
    verifiedAt: { type: Date, default: null },
    expiresAt: { type: Date, required: true },
  },
  { timestamps: true, collection: 'otp_codes' },
);
otpCodeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
applyCommon(otpCodeSchema);

export const OtpCode = mongoose.models.OtpCode || mongoose.model('OtpCode', otpCodeSchema);
