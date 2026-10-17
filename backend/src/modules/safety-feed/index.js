// Daily safety feed for miners (CLAUDE.md section 23.6). Cron (Asia/Kolkata) + on boot when today's feed is missing.
// Without GEMINI_API_KEY the endpoints answer 503 FEED_NOT_CONFIGURED: no canned rules are ever shown as "today's".
import { Router } from 'express';
import cron from 'node-cron';
import mongoose from 'mongoose';
import { z } from 'zod';
import { authenticate, requireRole } from '../../core/auth.js';
import { AppError, asyncHandler } from '../../core/errors.js';
import { validate } from '../../core/validate.js';
import { audit } from '../../core/audit.js';
import { publish } from '../../core/bus.js';
import { emitTo } from '../../core/socket.js';
import { logger } from '../../core/logger.js';
import { env } from '../../config/env.js';
import { istDay } from './feed.logic.js';
import { configured, generate, isRunning, latest, withLinks } from './feed.service.js';

const router = Router();
const notConfigured = () => new AppError(503, 'FEED_NOT_CONFIGURED', 'Set GEMINI_API_KEY (with Google Search grounding) in backend/.env for the daily safety feed');

async function runAndAnnounce(date, why) {
  const doc = await generate(date);
  publish('SafetyFeedUpdated', { date: doc.date, version: doc.version });
  emitTo(['role:miner', 'role:supervisor', 'role:admin'], 'safety:feed', { date: doc.date, version: doc.version });
  logger.info({ date: doc.date, version: doc.version, items: doc.items.length, dropped: doc.dropped, why }, 'safety feed generated');
  return doc;
}

router.get(
  '/today',
  authenticate(),
  asyncHandler(async (_req, res) => {
    const feed = await latest(istDay());
    if (feed) return res.json({ feed: await withLinks(feed) });
    if (!configured()) throw notConfigured();
    throw new AppError(404, 'FEED_NOT_READY', "Today's safety feed is being prepared", { generating: isRunning() });
  }),
);

router.get(
  '/',
  authenticate(),
  validate({ query: z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) }) }),
  asyncHandler(async (req, res) => {
    const feed = await latest(req.query.date);
    if (!feed) throw new AppError(404, 'NOT_FOUND', `No safety feed for ${req.query.date}`);
    res.json({ feed: await withLinks(feed) });
  }),
);

router.post(
  '/refresh',
  authenticate(),
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    if (!configured()) throw notConfigured();
    if (isRunning()) throw new AppError(409, 'FEED_BUSY', 'A feed is already being generated');
    try {
      const doc = await runAndAnnounce(istDay(), 'admin refresh');
      await audit(req.user, 'SAFETY_FEED_REFRESHED', 'safety_feed', `${doc.date}#${doc.version}`, { items: doc.items.length, dropped: doc.dropped });
      res.json({ feed: await withLinks(doc) });
    } catch (err) {
      if (err.code === 'FEED_NOT_CONFIGURED') throw notConfigured();
      throw new AppError(502, 'FEED_FAILED', `Could not build the feed: ${String(err.message).slice(0, 160)}`);
    }
  }),
);

async function init() {
  await mongoose.connection.collection('safety_feed').createIndex({ date: 1, version: -1 }, { unique: true }).catch(() => {});
  if (!configured()) return logger.warn('safety feed: GEMINI_API_KEY not set (or SAFETY_FEED_ENABLED=false); /api/safety-feed answers 503');
  const tick = (why) => runAndAnnounce(istDay(), why).catch((err) => logger.warn({ err: err.message }, 'safety feed generation failed'));
  if (cron.validate(env.SAFETY_FEED_CRON)) cron.schedule(env.SAFETY_FEED_CRON, () => tick('cron'), { timezone: 'Asia/Kolkata' });
  else logger.warn(`safety feed: SAFETY_FEED_CRON "${env.SAFETY_FEED_CRON}" is not a valid cron expression`);
  if (!(await latest(istDay()))) setTimeout(() => tick('boot'), 3000).unref?.();
}

export default { name: 'safety-feed', basePath: '/api/safety-feed', router, init };
