import { AppError } from '../../core/errors.js';
import { audit } from '../../core/audit.js';
import { logger } from '../../core/logger.js';
import { firebaseAuth } from '../../core/firebase.js';
import { User } from '../../models/User.js';
import { Zone } from '../../models/Zone.js';
import { consumeVerifiedEmail, requireVerifiedEmail } from '../otp/otp.service.js';
import { normalizeEmail } from '../otp/otp.logic.js';

export async function signup(req) {
  const b = req.body;
  const email = normalizeEmail(b.email);
  if (!req.firebase?.email || normalizeEmail(req.firebase.email) !== email) {
    throw new AppError(400, 'EMAIL_TOKEN_MISMATCH', 'Email does not match this account', { path: 'email' });
  }
  await requireVerifiedEmail(req.firebase);
  if (await User.exists({ firebaseUid: req.firebase.uid })) {
    throw new AppError(409, 'ALREADY_REGISTERED', 'This account already has a profile');
  }
  const zone = await Zone.findById(b.zoneId);
  if (!zone) throw new AppError(400, 'ZONE_NOT_FOUND', 'Zone not found', { path: 'zoneId' });

  // The role is authoritative in Mongo; the claim is only a convenience. Without a service account Firebase refuses it, which must not block sign-up.
  try {
    await firebaseAuth().setCustomUserClaims(req.firebase.uid, { role: b.role });
  } catch (err) {
    logger.warn({ err: err.message }, 'custom claim not set (service account missing?)');
  }
  let user;
  try {
    user = await User.create({
      firebaseUid: req.firebase.uid,
      role: b.role,
      status: 'active',
      fullName: b.fullName,
      employeeId: b.employeeId,
      email,
      designation: b.designation,
      experienceYears: b.experienceYears,
      dateOfJoining: new Date(b.dateOfJoining),
      dob: new Date(b.dob),
      bloodGroup: b.bloodGroup,
      mineName: b.mineName,
      zoneId: zone._id,
      shift: b.shift,
      address: b.address,
    });
  } catch (err) {
    if (err?.code === 11000) {
      const key = Object.keys(err.keyPattern || err.keyValue || {})[0] || '';
      if (key.startsWith('employeeId')) throw new AppError(409, 'DUPLICATE', 'This employee ID is already registered', { field: 'employeeId', path: 'employeeId' });
      if (key === 'email') throw new AppError(409, 'DUPLICATE', 'This email is already registered', { field: 'email', path: 'email' });
    }
    throw err;
  }
  if (b.role === 'supervisor') {
    try {
      await Zone.updateOne({ _id: zone._id }, { $addToSet: { supervisorIds: user._id } });
    } catch (err) {
      await User.deleteOne({ _id: user._id });
      throw err;
    }
  }
  await consumeVerifiedEmail(req.firebase);
  await audit(user, 'USER_SIGNUP', 'user', user._id, { role: b.role, zone: zone.code });
  return user;
}
