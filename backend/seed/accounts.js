/**
 * Demo logins are email accounts. SEED_EMAIL=you@gmail.com gives every demo account its own plus-address of one real
 * inbox, so every login code lands with you:  MIN-0105 -> you+min-0105@gmail.com
 */
export function demoEmailFor(employeeId, base = process.env.SEED_EMAIL) {
  const b = String(base || '').trim().toLowerCase();
  if (!/^[^@\s+]+@[^@\s]+\.[^@\s]+$/.test(b)) throw new Error('Set SEED_EMAIL=you@gmail.com (a real inbox you own) first');
  return b.replace('@', `+${String(employeeId).toLowerCase()}@`);
}

export const DEMO = {
  admin: { employeeId: 'ADM-0001', password: 'Admin1' },
  supervisorB: { employeeId: 'SUP-0012', password: 'Super1' },
  supervisorA: { employeeId: 'SUP-0011', password: 'Super1' },
  minerB: { employeeId: 'MIN-0105', password: 'Miner1' },
};
