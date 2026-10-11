import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { firebaseAuth } from './firebase.js';
import { AppError } from './errors.js';
import { logger } from './logger.js';

const devBypassOn = () => env.NODE_ENV === 'development' && env.DEV_AUTH_BYPASS === true;

export function logDevBypassWarning() {
  if (devBypassOn()) logger.warn('DEV_AUTH_BYPASS is ON (x-dev-user-id header accepted). Never use outside development.');
}

/** A server clock slightly behind Google's rejects brand-new tokens ("used too early"); one short wait fixes it. */
async function verifyWithSkewRetry(token) {
  try {
    return await firebaseAuth().verifyIdToken(token);
  } catch (err) {
    if (!/too early/i.test(String(err?.message))) throw err;
    await new Promise((r) => setTimeout(r, 1500));
    return firebaseAuth().verifyIdToken(token);
  }
}

const User = () => mongoose.model('User');

async function resolveUser(firebaseUid) {
  return User().findOne({ firebaseUid });
}

/**
 * authenticate({ allowUnregistered }) -> middleware.
 * Sets req.firebase (decoded token) and req.user (Mongo user).
 */
export function authenticate({ allowUnregistered = false } = {}) {
  return async (req, _res, next) => {
    try {
      if (devBypassOn() && req.headers['x-dev-user-id']) {
        const user = await User().findById(String(req.headers['x-dev-user-id']));
        if (!user) throw new AppError(401, 'UNAUTHENTICATED', 'Unknown dev user');
        req.user = user;
        req.firebase = { uid: user.firebaseUid, email: user.email, dev: true };
        return next();
      }
      const h = req.headers.authorization || '';
      const m = /^Bearer\s+(.+)$/i.exec(h);
      if (!m) throw new AppError(401, 'UNAUTHENTICATED', 'Missing bearer token');
      let decoded;
      try {
        decoded = await verifyWithSkewRetry(m[1]);
      } catch (err) {
        logger.warn({ firebaseCode: err?.code, reason: String(err?.message || '').slice(0, 160) }, 'ID token rejected');
        throw new AppError(401, 'UNAUTHENTICATED', 'Invalid or expired token');
      }
      req.firebase = decoded;
      const user = await resolveUser(decoded.uid);
      if (!user) {
        if (allowUnregistered) return next();
        throw new AppError(403, 'USER_NOT_REGISTERED', 'No profile for this account');
      }
      if (user.status !== 'active') throw new AppError(403, 'ACCOUNT_INACTIVE', 'Account is inactive');
      req.user = user;
      next();
    } catch (e) {
      next(e);
    }
  };
}

export function requireRole(...roles) {
  return (req, _res, next) => {
    if (!req.user) return next(new AppError(401, 'UNAUTHENTICATED', 'Not authenticated'));
    if (!roles.includes(req.user.role)) return next(new AppError(403, 'FORBIDDEN_ROLE', `Requires role: ${roles.join(' or ')}`));
    next();
  };
}

/** Supervisor of the zone, or admin. Used by many routes. */
export function isZoneStaff(user, zoneId) {
  if (!user) return false;
  if (user.role === 'admin') return true;
  return user.role === 'supervisor' && String(user.zoneId) === String(zoneId);
}

/** Socket.io handshake: returns the Mongo user or throws. */
export async function verifySocketHandshake(handshake) {
  const token = handshake.auth?.token;
  if (devBypassOn() && handshake.auth?.devUserId) {
    const u = await User().findById(String(handshake.auth.devUserId));
    if (u) return u;
  }
  if (!token) throw new Error('UNAUTHENTICATED');
  const decoded = await verifyWithSkewRetry(token);
  const user = await resolveUser(decoded.uid);
  if (!user) throw new Error('USER_NOT_REGISTERED');
  if (user.status !== 'active') throw new Error('ACCOUNT_INACTIVE');
  return user;
}
