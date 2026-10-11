// ML_MODE=mock: deterministic output derived from the image sha256, so UI and pipeline work needs no API key.
// Last hex digit of the hash picks the scenario: 0-3 compliant, 4-6 helmet missing, 7-f needs review.
// Mock output never reports an emergency: an emergency starts a real crisis (calls, banners), which a fake analysis must not do.
const lastNibble = (sha) => parseInt(sha.slice(-1), 16);

export function mockScenario(sha) {
  const n = lastNibble(sha);
  if (n <= 3) return 'compliant';
  if (n <= 6) return 'no_helmet';
  return 'needs_review';
}

const present = (key) => ({ key, status: 'PRESENT', confidence: 0.9, evidence: `${key.toLowerCase().replace(/_/g, ' ')} clearly visible on the worker` });

export function mockPpeRaw(sha, required) {
  const scenario = mockScenario(sha);
  const items = required.map(present);
  let summary = 'All required PPE is visible.';
  let emergency = { detected: false, possible: false, type: 'NONE', confidence: 0, evidence: '' };
  let full = true;
  if (scenario === 'no_helmet') {
    const i = items.findIndex((x) => x.key === 'HELMET');
    if (i >= 0) items[i] = { key: 'HELMET', status: 'ABSENT', confidence: 0.92, evidence: 'head is bare; no hard hat visible' };
    summary = 'Helmet is missing.';
  } else if (scenario === 'needs_review') {
    const i = items.findIndex((x) => x.key === 'GLOVES');
    if (i >= 0) items[i] = { key: 'GLOVES', status: 'UNCERTAIN', confidence: 0.45, evidence: '' };
    full = false;
    summary = 'Gloves cannot be confirmed; feet are out of frame.';
  }
  return {
    mode: 'PPE_COMPLIANCE', image_relevance: 'RELEVANT', framing: { full_body_visible: full, persons_count: 1, notes: 'mock' }, items, emergency, conflicts: [],
    limitations: ['Mock mode: not a real analysis'], summary, report: { observations: ['Mock analysis'], risks: [], recommended_actions: ['Supervisor to review'] },
  };
}

export function mockHazardRaw(sha, context = {}) {
  const category = context.category ?? 'OTHER';
  const crit = false;
  return {
    mode: 'HAZARD_SCENE', image_relevance: 'RELEVANT', hazard_description: crit ? 'Open flame and dense smoke in the roadway.' : 'A loose cable lies across the walkway.',
    category_claimed: category, category_observed: crit ? 'FIRE_SMOKE' : category, category_matches: !crit, severity: crit ? 'CRITICAL' : 'MEDIUM', severity_confidence: crit ? 0.9 : 0.7,
    affected_area_estimate: 'About 5 m of roadway', emergency: crit ? { detected: true, possible: true, type: 'FIRE', confidence: 0.9, evidence: 'flames' } : { detected: false, possible: false, type: 'NONE', confidence: 0, evidence: '' },
    limitations: ['Mock mode: not a real analysis'], summary: crit ? 'Fire in the roadway; evacuate.' : 'Trip hazard from a loose cable.', report: { observations: ['Mock analysis'], risks: ['Trip or shock'], recommended_actions: ['Isolate and make safe'] },
  };
}
