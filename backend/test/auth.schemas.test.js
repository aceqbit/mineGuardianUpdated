import test from 'node:test';
import assert from 'node:assert/strict';
import { signupSchema } from '../src/modules/auth/auth.schemas.js';

const valid = () => ({
  role: 'miner',
  fullName: 'Ravi Kumar',
  employeeId: 'min-0150',
  email: 'ravi@example.com',
  designation: 'Miner',
  experienceYears: 5,
  dateOfJoining: '2020-01-01',
  dob: '1990-05-05',
  bloodGroup: 'O+',
  mineName: 'MG Demo Colliery',
  zoneId: '64b8f0f2f1a2b3c4d5e6f701',
  shift: 'B',
});

test('valid body passes and employeeId is uppercased', () => {
  const r = signupSchema.parse(valid());
  assert.equal(r.employeeId, 'MIN-0150');
});

test('age 17 fails', () => {
  const b = valid();
  b.dob = new Date(Date.now() - 17 * 365.25 * 24 * 3600 * 1000).toISOString().slice(0, 10);
  assert.throws(() => signupSchema.parse(b));
});

test('role admin fails; unknown keys fail (strict)', () => {
  assert.throws(() => signupSchema.parse({ ...valid(), role: 'admin' }));
  assert.throws(() => signupSchema.parse({ ...valid(), extra: 1 }));
});

test('future joining date fails', () => {
  assert.throws(() => signupSchema.parse({ ...valid(), dateOfJoining: '2999-01-01' }));
});

test('there is no phone or emergency-contact field any more (strict body)', () => {
  assert.throws(() => signupSchema.parse({ ...valid(), phone: { isoCode: 'IN', dialCode: '91', national: '9876500150' } }));
  assert.throws(() => signupSchema.parse({ ...valid(), emergencyContact: { name: 'A B', relation: 'Spouse' } }));
});

test('email is required and must look like an email', () => {
  const b = valid();
  delete b.email;
  assert.throws(() => signupSchema.parse(b));
  assert.throws(() => signupSchema.parse({ ...valid(), email: 'not-an-email' }));
});
