import nodemailer from 'nodemailer';
import { env } from '../config/env.js';
import { logger } from './logger.js';

let transporter;
const getTransporter = () => (transporter ??= nodemailer.createTransport({ service: 'gmail', auth: { user: env.GMAIL_USER, pass: env.GMAIL_APP_PASSWORD } }));

export const mailConfigured = () => Boolean(env.GMAIL_USER && env.GMAIL_APP_PASSWORD);

/** a***@gmail.com: what the app may show and what logs may contain. */
export const maskEmail = (e) => {
  const [local = '', domain = ''] = String(e).split('@');
  return `${local.slice(0, 1)}***@${domain}`;
};

/** Sends one plain-text mail through Gmail SMTP. Never throws; failures return { error }. */
export async function sendMail(to, subject, text) {
  try {
    if (!mailConfigured()) return { error: 'NOT_CONFIGURED' };
    await getTransporter().sendMail({ from: `Mine Guardian <${env.GMAIL_USER}>`, to, subject, text });
    return { ok: true };
  } catch (err) {
    logger.warn({ err: err.message, to: maskEmail(to) }, 'mail send failed');
    return { error: err.message };
  }
}

/** Used by dev/check-setup.js: logs in to Gmail without sending anything. */
export async function verifyMailer() {
  await getTransporter().verify();
}
