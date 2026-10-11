import { z } from 'zod';
import { SHIFT } from '../../contracts/enums.js';
import { objectId } from '../../core/validate.js';

export const DESIGNATIONS = ['Miner', 'Shot-firer', 'Mining Sirdar', 'Overman', 'Electrician', 'Fitter', 'Surveyor', 'Pump Operator', 'Supervisor', 'Other'];
export const BLOOD_GROUPS = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
export const RELATIONS = ['Spouse', 'Parent', 'Sibling', 'Child', 'Friend', 'Other'];

const ageOn = (iso, now = new Date()) => {
  const d = new Date(iso);
  let age = now.getUTCFullYear() - d.getUTCFullYear();
  const m = now.getUTCMonth() - d.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < d.getUTCDate())) age--;
  return age;
};

const isoDate = z.string().trim().refine((v) => !Number.isNaN(Date.parse(v)), 'Invalid date');

export const signupSchema = z
  .object({
    role: z.enum(['miner', 'supervisor']),
    fullName: z.string().trim().min(2).max(60).regex(/^[\p{L} .'-]+$/u, 'Letters, spaces and . \' - only'),
    employeeId: z
      .string()
      .trim()
      .regex(/^[A-Za-z]{2,4}-?\d{3,8}$/, 'Invalid employee ID')
      .transform((s) => s.toUpperCase()),
    email: z.string().trim().email().max(120),
    designation: z.enum(DESIGNATIONS),
    experienceYears: z.number().int().min(0).max(45),
    dateOfJoining: isoDate.refine((v) => new Date(v) <= new Date(), 'Date of joining cannot be in the future'),
    dob: isoDate.refine((v) => {
      const a = ageOn(v);
      return a >= 18 && a <= 65;
    }, 'Age must be between 18 and 65'),
    bloodGroup: z.enum(BLOOD_GROUPS),
    mineName: z.string().trim().min(2).max(80),
    zoneId: objectId,
    shift: z.enum(SHIFT),
    address: z.string().trim().max(200).optional(),
  })
  .strict();

export const fcmTokenSchema = z.object({ token: z.string().min(20).max(4096) }).strict();
