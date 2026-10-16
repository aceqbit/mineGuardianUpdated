// Shared contract v1 enums. Frozen after S0.1. Identical strings in mobile/lib/contracts/enums.dart.
const e = (...v) => Object.freeze(v);

export const ROLE = e('miner', 'supervisor', 'admin');
export const USER_STATUS = e('active', 'inactive');
export const SHIFT = e('A', 'B', 'C');
export const SHIFT_HOURS = Object.freeze({ A: ['06:00', '14:00'], B: ['14:00', '22:00'], C: ['22:00', '06:00'] });
export const TIMEZONE = 'Asia/Kolkata';
export const PPE_KEY = e('HELMET', 'CAP_LAMP', 'REFLECTIVE_VEST', 'SAFETY_BOOTS', 'GLOVES', 'SELF_RESCUER', 'DUST_MASK', 'EAR_PROTECTION', 'EYE_PROTECTION', 'GAS_DETECTOR');
export const PPE_STATUS = e('PRESENT', 'ABSENT', 'UNCERTAIN', 'NOT_REQUIRED');
export const CHECKIN_STATUS = e('RECEIVED', 'ANALYZING', 'PREDICTED', 'REVIEWED', 'FAILED_AI', 'REJECTED_QUALITY');
export const VERDICT = e('COMPLIANT', 'NON_COMPLIANT', 'NEEDS_MANUAL_REVIEW');
export const CRITICALITY = e('NONE', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
export const HAZARD_CATEGORY = e('GAS_LEAK', 'ROOF_FALL', 'FIRE_SMOKE', 'FLOODING', 'ELECTRICAL', 'EQUIPMENT_FAILURE', 'VENTILATION_FAILURE', 'OTHER');
export const HAZARD_SEVERITY = e('LOW', 'MEDIUM', 'CRITICAL');
export const HAZARD_STATUS = e('OPEN', 'ACKNOWLEDGED', 'CLOSED', 'REJECTED');
export const SOS_STATUS = e('ACTIVE', 'CANCELLED', 'RESOLVED');
export const CRISIS_STATUS = e('ACTIVE', 'RESOLVED');
export const CRISIS_TRIGGER = e('SOS', 'ML_EMERGENCY', 'HAZARD_CRITICAL', 'SUPERVISOR_ESCALATION', 'MANUAL');
export const DECISION_ACTION = e('CONFIRM', 'OVERRIDE', 'ESCALATE');
export const ESCALATION_LEVEL = e('ATTENTION', 'EMERGENCY');
export const EMERGENCY_TYPE = e('NONE', 'FIRE', 'SMOKE', 'FLOODING', 'ROOF_FALL', 'INJURED_PERSON', 'GAS_OR_DUST_CLOUD', 'ELECTRICAL_ARC', 'TRAPPED_PERSON', 'OTHER');
export const RISK_BAND = e('GREEN', 'AMBER', 'RED');
export const INTEGRITY_FLAG = e('STALE_PHOTO', 'CLOCK_SKEW', 'NO_EXIF', 'DUPLICATE_HASH', 'OUTSIDE_ZONE', 'LOW_GPS_ACCURACY', 'OUT_OF_SHIFT', 'OFFLINE_DELAYED', 'GALLERY_SOURCE');
export const ACCOUNTED_STATUS = e('SAFE', 'MISSING', 'INJURED', 'UNKNOWN');
export const BROADCAST_SCOPE = e('ALL', 'ZONE', 'ROLE');
export const BROADCAST_PRIORITY = e('INFO', 'URGENT', 'EMERGENCY');
export const CONTACT_CATEGORY = e('POLICE', 'FIRE', 'MINE_RESCUE', 'AMBULANCE', 'DISTRICT_MINING_AUTHORITY');
export const REVIEW_STATUS = e('PENDING_REVIEW', 'DECIDED');
// Add-on pack X (CLAUDE.md section 23, CONTRACT commit X0). Additive only.
export const ROUTE_MODE = e('LEAST_HINDRANCE', 'MOST_LIGHT', 'MOST_AID', 'DIRECT');
export const AID_TYPE = e('FIRST_AID', 'TOOL_STATION', 'PHONE', 'SCSR_CACHE', 'FIRE_EXTINGUISHER');
export const POSITION_SOURCE = e('GPS', 'FUSED', 'PDR');
export const SAFETY_ITEM_KIND = e('RULE', 'REACT', 'PREVENT', 'LESSON');
export const VOICE_CALL_STATUS = e('QUEUED', 'RINGING', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'DRY_RUN');
export const PRESENCE = e('LIVE', 'STALE', 'OFFLINE');
