import 'dotenv/config';
import { z } from 'zod';

const bool = (def) =>
  z.preprocess((v) => (v === undefined || v === '' ? def : String(v).toLowerCase() === 'true'), z.boolean());
const optStr = z.string().optional().default('');

const schema = z
  .object({
  PORT: z.coerce.number().int().default(4000),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  CORS_ORIGINS: z.string().default('*'),
  PUBLIC_BASE_URL: z.string().default('http://localhost:4000'),
  MONGODB_URI: z.string().min(1, 'required'),
  FIREBASE_PROJECT_ID: z.string().min(1, 'required'),
  STORAGE_DRIVER: z.enum(['firebase', 'local']).default('firebase'),
  LOCAL_STORAGE_DIR: z.string().default('./storage-data'),
  FIREBASE_STORAGE_BUCKET: optStr,
  GOOGLE_APPLICATION_CREDENTIALS: z.string().min(1, 'required').default('./secrets/firebase-sa.json'),
  DEV_AUTH_BYPASS: bool(false),
  DEMO_FAST_MODE: bool(false),
  GEOFENCE_ENFORCE: bool(false),
  SHIFT_WINDOW_ENFORCE: bool(false),
  DEMO_ANCHOR_LAT: z.coerce.number().default(23.746),
  DEMO_ANCHOR_LNG: z.coerce.number().default(86.415),
  GEMINI_API_KEY: optStr,
  GEMINI_MODEL: z.string().default('gemini-3.8-flash'),
  GEMINI_FALLBACK_MODEL: z.string().default('gemini-3.5-flash'),
  GEMINI_TEMPERATURE: optStr,
  ML_MODE: z.enum(['hybrid', 'gemini_only', 'yolo_only', 'mock']).default('hybrid'),
  YOLO_PROVIDER: z.enum(['roboflow', 'onnx', 'none']).default('roboflow'),
  ROBOFLOW_API_KEY: optStr,
  ROBOFLOW_MODEL: z.string().default('personal-protective-equipment-combined-model/8'),
  ONNX_MODEL_PATH: z.string().default('./models/ppe-yolov8n.onnx'),
  ONNX_CLASSES: optStr,
  TWILIO_ACCOUNT_SID: optStr,
  TWILIO_AUTH_TOKEN: optStr,
  TWILIO_FROM_NUMBER: optStr,
  TWILIO_DRY_RUN: bool(true),
  OTP_REQUIRED: bool(true),
  GMAIL_USER: optStr,
  GMAIL_APP_PASSWORD: optStr,
  TWILIO_CALL_ALLOWLIST: optStr,
  SLA_MINUTES: z.coerce.number().default(30),
  SLA_REMINDER_BASE_MINUTES: z.coerce.number().default(5),
  // Add-on pack X (CLAUDE.md section 23.1), all optional.
  TRACKING_ENABLED: bool(true),
  TRACKING_STALE_SEC: z.coerce.number().int().positive().default(30),
  TRACKING_OFFLINE_SEC: z.coerce.number().int().positive().default(120),
  ORS_API_KEY: optStr,
  VOICE_AGENT_MODE: z.enum(['say', 'relay']).default('say'),
  VOICE_AGENT_MAX_SEC: z.coerce.number().int().positive().default(180),
  SAFETY_FEED_ENABLED: bool(true),
  SAFETY_FEED_CRON: z.string().default('0 5,11,17 * * *'),
  SAFETY_VIDEO_MODE: z.enum(['storyboard', 'veo', 'off']).default('storyboard'),
  VEO_MODEL: optStr,
  SAFETY_SOURCE_ALLOWLIST: z.string().default('dgms.gov.in,ilo.org,osha.gov,msha.gov,hse.gov.uk'),
})
  .superRefine((v, ctx) => {
    if (v.STORAGE_DRIVER === 'firebase' && !v.FIREBASE_STORAGE_BUCKET) ctx.addIssue({ code: 'custom', path: ['FIREBASE_STORAGE_BUCKET'], message: 'required (or set STORAGE_DRIVER=local)' });
  });

export function parseEnv(source = process.env, { exit = true } = {}) {
  const r = schema.safeParse(source);
  if (!r.success) {
    const lines = r.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`);
    const msg = `Invalid or missing environment variables:\n${lines.join('\n')}`;
    if (exit) {
      console.error(msg);
      process.exit(1);
    }
    throw new Error(msg);
  }
  const v = r.data;
  const div = v.DEMO_FAST_MODE ? 15 : 1;
  return Object.freeze({
    ...v,
    isDev: v.NODE_ENV === 'development',
    slaMinutes: v.SLA_MINUTES / div,
    slaReminderBaseMinutes: v.SLA_REMINDER_BASE_MINUTES / div,
  });
}

const testing = process.env.NODE_ENV === 'test' || Boolean(process.env.NODE_TEST_CONTEXT);
function load() {
  if (!testing) return parseEnv(process.env);
  try {
    return parseEnv(process.env, { exit: false });
  } catch {
    return Object.freeze({ NODE_ENV: 'test', isDev: false, TWILIO_DRY_RUN: true, slaMinutes: 30, slaReminderBaseMinutes: 5 });
  }
}
export const env = load();
