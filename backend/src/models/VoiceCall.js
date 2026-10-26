import mongoose from 'mongoose';
import { VOICE_CALL_STATUS } from '../contracts/enums.js';
import { applyCommon } from './_plugin.js';

const { Schema } = mongoose;

/** Add-on X5: one AI voice-agent call. The number is stored masked only; transcripts are never stored. */
const voiceCallSchema = new Schema(
  {
    callerId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    targetType: { type: String, enum: ['user', 'contact'], required: true },
    targetId: { type: Schema.Types.ObjectId, required: true },
    targetLabel: { type: String, required: true },
    toMasked: String,
    mode: { type: String, enum: ['say', 'relay'], required: true },
    status: { type: String, enum: VOICE_CALL_STATUS, default: 'QUEUED' },
    sid: String,
    dryRun: { type: Boolean, default: false },
    reason: String,
    briefingChars: Number,
    turns: { type: Number, default: 0 },
    relayToken: { type: String, select: false },
    error: String,
    endedAt: Date,
  },
  { timestamps: true, collection: 'voice_calls' },
);
voiceCallSchema.index({ callerId: 1, createdAt: -1 });
voiceCallSchema.index({ sid: 1 }, { sparse: true });
applyCommon(voiceCallSchema);
export const VoiceCall = mongoose.models.VoiceCall || mongoose.model('VoiceCall', voiceCallSchema);
