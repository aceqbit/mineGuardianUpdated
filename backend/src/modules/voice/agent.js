// Gemini for the voice agent (CLAUDE.md section 23.5). Its own small client (no import of the analyser's internals).
// Every call has a timeout; on any failure the caller gets the fixed template, never silence or invented text.
import { GoogleGenAI } from '@google/genai';
import { env } from '../../config/env.js';
import { logger } from '../../core/logger.js';
import { AGENT_SYSTEM_PROMPT, FIRST_AID_NOTES, briefingPrompt, greetingPrompt } from './agent.prompt.js';
import { MAX_TURNS, VOICE_MAX, packetLines, templateBriefing } from './voice.logic.js';

let client = null;
const ai = () => (env.GEMINI_API_KEY ? (client ??= new GoogleGenAI({ apiKey: env.GEMINI_API_KEY })) : null);
const SAFETY = [
  { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_ONLY_HIGH' },
  { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
  { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
  { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
];
const config = (maxOutputTokens) => ({ systemInstruction: AGENT_SYSTEM_PROMPT, maxOutputTokens, safetySettings: SAFETY });
const withTimeout = (p, ms) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), ms))]);
const clean = (s) => String(s ?? '').replace(/[*_#`>]/g, '').replace(/\s+/g, ' ').trim();

export const packetText = (packet) => [...packetLines(packet), FIRST_AID_NOTES].join('\n');

async function oneShot(prompt, max, ms = 8000) {
  const c = ai();
  if (!c) return null;
  try {
    const res = await withTimeout(c.models.generateContent({ model: env.GEMINI_MODEL, contents: [{ role: 'user', parts: [{ text: prompt }] }], config: config(200) }), ms);
    const t = clean(res?.text);
    return t ? t.slice(0, max) : null;
  } catch (err) {
    logger.warn({ err: err.message }, 'voice agent: gemini failed, using the template');
    return null;
  }
}

/** `say` mode: the spoken briefing. Returns { text, ai }. */
export async function briefing(packet, targetLabel) {
  const t = await oneShot(briefingPrompt(packetText(packet), targetLabel), VOICE_MAX);
  return t ? { text: t, ai: true } : { text: templateBriefing(packet, targetLabel), ai: false };
}

/** `relay` mode: the welcome greeting Twilio speaks as soon as the call connects. */
export async function greeting(packet, targetLabel) {
  const t = await oneShot(greetingPrompt(packetText(packet), targetLabel), 300, 6000);
  return t ?? `${templateBriefing(packet, targetLabel).slice(0, 260)} Can you hear me?`;
}

/**
 * `relay` mode: one reply, streamed. `history` = [{role:'user'|'model', text}]; `onToken(text)` is called per chunk.
 * Returns the full reply. Falls back to a fixed line on any failure.
 */
export async function reply(packet, history, utterance, onToken, { ms = 12000 } = {}) {
  const c = ai();
  const fallback = 'I am sorry, I cannot answer that right now. I will ask the caller to call you back.';
  if (!c) {
    onToken(fallback);
    return fallback;
  }
  const turns = history.slice(-2 * MAX_TURNS);
  const contents = [
    { role: 'user', parts: [{ text: `CONTEXT\n${packetText(packet)}` }] },
    { role: 'model', parts: [{ text: 'Understood. I will use only this context.' }] },
    ...turns.map((h) => ({ role: h.role, parts: [{ text: h.text }] })),
    { role: 'user', parts: [{ text: String(utterance).slice(0, 600) }] },
  ];
  let full = '';
  try {
    const stream = await withTimeout(c.models.generateContentStream({ model: env.GEMINI_MODEL, contents, config: config(160) }), ms);
    for await (const chunk of stream) {
      const t = (chunk?.text ?? '').replace(/[*_#`>]/g, '');
      if (t) {
        full += t;
        onToken(t);
      }
    }
  } catch (err) {
    logger.warn({ err: err.message }, 'voice agent: streaming reply failed');
  }
  if (!clean(full)) {
    onToken(fallback);
    return fallback;
  }
  return clean(full);
}
