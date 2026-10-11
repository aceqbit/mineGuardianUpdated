// Dev tool: checks the email-OTP / real-call / Google-map setup and prints PASS / FAIL / TODO per item. Prints no secrets.
// Usage (from backend/):  node dev/check-setup.js            (Google check also needs GOOGLE_MAPS_API_KEY in the shell)
import twilioLib from 'twilio';
import { env } from '../src/config/env.js';
import { allowedTargets } from '../src/core/twilio.js';
import { mailConfigured, verifyMailer } from '../src/core/mailer.js';

const rows = [];
const add = (status, item, note = '') => rows.push({ status, item, note });

if (!mailConfigured()) {
  add('TODO', 'Email codes (Gmail)', 'set GMAIL_USER and GMAIL_APP_PASSWORD in backend/.env (2-Step Verification on, App Password from myaccount.google.com/apppasswords)');
} else {
  try {
    await verifyMailer();
    add('PASS', 'Email codes (Gmail)', 'Gmail SMTP login works');
  } catch (e) {
    add('FAIL', 'Email codes (Gmail)', e.message);
  }
}

const haveTwilio = Boolean(env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN);
if (!haveTwilio) {
  add('TODO', 'Twilio account (SOS calls only)', 'set TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN in backend/.env');
} else {
  const client = twilioLib(env.TWILIO_ACCOUNT_SID, env.TWILIO_AUTH_TOKEN);
  let trial = true;
  try {
    const acc = await client.api.accounts(env.TWILIO_ACCOUNT_SID).fetch();
    trial = acc.type === 'Trial';
    add('PASS', 'Twilio credentials', `account ${acc.status}, type ${acc.type}`);
  } catch (e) {
    add('FAIL', 'Twilio credentials', e.message);
  }

  const list = allowedTargets();
  let verified = [];
  try {
    verified = (await client.outgoingCallerIds.list({ limit: 50 })).map((v) => v.phoneNumber);
  } catch (e) {
    add('FAIL', 'Verified numbers', e.message);
  }
  if (!list.length) add('TODO', 'TWILIO_CALL_ALLOWLIST', 'live calls/SMS reach nobody until you list your verified numbers (E.164, comma separated)');
  for (const n of list) {
    const ok = !trial || verified.includes(n);
    add(ok ? 'PASS' : 'FAIL', `Allowlisted ${n.slice(0, 5)}******${n.slice(-2)}`, ok ? (trial ? 'verified in Twilio' : 'ok') : 'not verified: Console > Phone Numbers > Verified Caller IDs');
  }

  if (!env.TWILIO_FROM_NUMBER) add('TODO', 'TWILIO_FROM_NUMBER', 'needed for crisis calls and SMS (a Twilio number you own)');
  else {
    try {
      const mine = await client.incomingPhoneNumbers.list({ limit: 50 });
      add(mine.some((m) => m.phoneNumber === env.TWILIO_FROM_NUMBER) ? 'PASS' : 'FAIL', 'TWILIO_FROM_NUMBER', 'must be a number on this Twilio account');
    } catch (e) {
      add('FAIL', 'TWILIO_FROM_NUMBER', e.message);
    }
  }

  try {
    const p = await client.voice.v1.dialingPermissions.countries('IN').fetch();
    const on = p.lowRiskNumbersEnabled || p.highRiskSpecialNumbersEnabled || p.highRiskTollfraudNumbersEnabled;
    add(on ? 'PASS' : 'FAIL', 'Voice permission for India', on ? 'enabled' : 'enable India in Console > Voice > Settings > Geo permissions');
  } catch (e) {
    add('TODO', 'Voice permission for India', `could not read it (${e.status ?? e.message}); check Console > Voice > Settings > Geo permissions`);
  }
}

add(env.TWILIO_DRY_RUN ? 'TODO' : 'PASS', 'TWILIO_DRY_RUN', env.TWILIO_DRY_RUN ? 'true: calls are only logged. Set false (with the allowlist) for real calls' : 'false: live, limited to the allowlist');

const gkey = process.env.GOOGLE_MAPS_API_KEY;
if (!gkey) add('TODO', 'Google Maps key', 'export GOOGLE_MAPS_API_KEY in this shell to test it, and pass it to the app with --dart-define');
else {
  try {
    const r = await fetch(`https://tile.googleapis.com/v1/createSession?key=${encodeURIComponent(gkey)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mapType: 'roadmap', language: 'en-IN', region: 'IN' }),
    });
    const j = await r.json();
    add(r.ok && j.session ? 'PASS' : 'FAIL', 'Google Map Tiles API', r.ok ? 'session created' : (j?.error?.message ?? `HTTP ${r.status}`));
  } catch (e) {
    add('FAIL', 'Google Map Tiles API', e.message);
  }
}

console.table(rows);
process.exit(rows.some((r) => r.status === 'FAIL') ? 1 : 0);
