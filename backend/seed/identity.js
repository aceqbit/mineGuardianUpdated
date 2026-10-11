import fs from 'node:fs';

// Firebase email/password identities through the public Identity Toolkit REST API: no service account needed.
// The web API key comes from the shell (FIREBASE_WEB_API_KEY) or from the Flutter app's own firebase_options.dart.
function webApiKey() {
  if (process.env.FIREBASE_WEB_API_KEY) return process.env.FIREBASE_WEB_API_KEY;
  const src = fs.readFileSync(new URL('../../mobile/lib/firebase_options.dart', import.meta.url), 'utf8');
  return /apiKey:\s*'([^']+)'/.exec(src)?.[1];
}

async function call(op, email, password) {
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:${op}?key=${webApiKey()}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const j = await res.json();
  if (!res.ok) throw new Error(j?.error?.message || `${op} failed`);
  return j;
}

/** Creates the login (or signs in to the existing one) and returns its Firebase uid. Fails if it exists with another password. */
export async function ensureIdentity(email, password) {
  try {
    return (await call('signUp', email, password)).localId;
  } catch (e) {
    if (e.message !== 'EMAIL_EXISTS') throw e;
    return (await call('signInWithPassword', email, password)).localId;
  }
}

/** ID token for a login (used by dev tools and smoke tests). */
export async function signInToken(email, password) {
  return (await call('signInWithPassword', email, password)).idToken;
}
