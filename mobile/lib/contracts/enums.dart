import 'package:flutter/material.dart';

/// Contract v1 enums. Wire strings are identical to backend/src/contracts/enums.js.
abstract interface class WireEnum {
  String get wire;
}

T _fromWire<T extends WireEnum>(List<T> values, String wire, String name) {
  for (final v in values) {
    if (v.wire == wire) return v;
  }
  throw ArgumentError('Unknown $name wire value: $wire');
}

enum Role implements WireEnum {
  miner('miner'),
  supervisor('supervisor'),
  admin('admin');

  const Role(this.wire);
  @override
  final String wire;
  static Role fromWire(String w) => _fromWire(values, w, 'Role');
  String get label => switch (this) { Role.miner => 'Miner', Role.supervisor => 'Supervisor', Role.admin => 'Admin' };
}

enum UserStatus implements WireEnum {
  active('active'),
  inactive('inactive');

  const UserStatus(this.wire);
  @override
  final String wire;
  static UserStatus fromWire(String w) => _fromWire(values, w, 'UserStatus');
}

enum Shift implements WireEnum {
  a('A', '06:00', '14:00'),
  b('B', '14:00', '22:00'),
  c('C', '22:00', '06:00');

  const Shift(this.wire, this.start, this.end);
  @override
  final String wire;
  final String start;
  final String end;
  static Shift fromWire(String w) => _fromWire(values, w, 'Shift');
  String get window => '$start–$end';
}

enum PpeKey implements WireEnum {
  helmet('HELMET', 'Helmet', Icons.engineering),
  capLamp('CAP_LAMP', 'Cap lamp', Icons.flashlight_on),
  reflectiveVest('REFLECTIVE_VEST', 'Reflective vest', Icons.checkroom),
  safetyBoots('SAFETY_BOOTS', 'Safety boots', Icons.hiking),
  gloves('GLOVES', 'Gloves', Icons.back_hand),
  selfRescuer('SELF_RESCUER', 'Self-rescuer', Icons.air),
  dustMask('DUST_MASK', 'Dust mask', Icons.masks),
  earProtection('EAR_PROTECTION', 'Ear protection', Icons.hearing),
  eyeProtection('EYE_PROTECTION', 'Eye protection', Icons.visibility),
  gasDetector('GAS_DETECTOR', 'Gas detector', Icons.sensors);

  const PpeKey(this.wire, this.label, this.icon);
  @override
  final String wire;
  final String label;
  final IconData icon;
  static PpeKey fromWire(String w) => _fromWire(values, w, 'PpeKey');
}

enum PpeStatus implements WireEnum {
  present('PRESENT'),
  absent('ABSENT'),
  uncertain('UNCERTAIN'),
  notRequired('NOT_REQUIRED');

  const PpeStatus(this.wire);
  @override
  final String wire;
  static PpeStatus fromWire(String w) => _fromWire(values, w, 'PpeStatus');
}

enum CheckinStatus implements WireEnum {
  received('RECEIVED'),
  analyzing('ANALYZING'),
  predicted('PREDICTED'),
  reviewed('REVIEWED'),
  failedAi('FAILED_AI'),
  rejectedQuality('REJECTED_QUALITY');

  const CheckinStatus(this.wire);
  @override
  final String wire;
  static CheckinStatus fromWire(String w) => _fromWire(values, w, 'CheckinStatus');
}

enum Verdict implements WireEnum {
  compliant('COMPLIANT', 'Compliant'),
  nonCompliant('NON_COMPLIANT', 'Non-compliant'),
  needsManualReview('NEEDS_MANUAL_REVIEW', 'Needs manual review');

  const Verdict(this.wire, this.label);
  @override
  final String wire;
  final String label;
  static Verdict fromWire(String w) => _fromWire(values, w, 'Verdict');
}

enum Criticality implements WireEnum {
  none('NONE'),
  low('LOW'),
  medium('MEDIUM'),
  high('HIGH'),
  critical('CRITICAL');

  const Criticality(this.wire);
  @override
  final String wire;
  static Criticality fromWire(String w) => _fromWire(values, w, 'Criticality');
}

enum HazardCategory implements WireEnum {
  gasLeak('GAS_LEAK', 'Gas leak / smell', 'Strange smell, hissing or detector alarm', Icons.cloud),
  roofFall('ROOF_FALL', 'Roof or side fall', 'Loose roof, cracks or falling rock', Icons.landslide),
  fireSmoke('FIRE_SMOKE', 'Fire or smoke', 'Flames, heat or smoke visible', Icons.local_fire_department),
  flooding('FLOODING', 'Water / flooding', 'Water inrush or rising water', Icons.water),
  electrical('ELECTRICAL', 'Electrical danger', 'Exposed cable, sparking or shock risk', Icons.bolt),
  equipmentFailure('EQUIPMENT_FAILURE', 'Equipment failure', 'Broken guard, machine or conveyor fault', Icons.build),
  ventilationFailure('VENTILATION_FAILURE', 'Ventilation failure', 'Fan stopped or airflow blocked', Icons.wind_power),
  other('OTHER', 'Other', 'Anything else unsafe', Icons.warning_amber);

  const HazardCategory(this.wire, this.label, this.hint, this.icon);
  @override
  final String wire;
  final String label;
  final String hint;
  final IconData icon;
  static HazardCategory fromWire(String w) => _fromWire(values, w, 'HazardCategory');
}

enum HazardSeverity implements WireEnum {
  low('LOW'),
  medium('MEDIUM'),
  critical('CRITICAL');

  const HazardSeverity(this.wire);
  @override
  final String wire;
  static HazardSeverity fromWire(String w) => _fromWire(values, w, 'HazardSeverity');
}

enum HazardStatus implements WireEnum {
  open('OPEN'),
  acknowledged('ACKNOWLEDGED'),
  closed('CLOSED'),
  rejected('REJECTED');

  const HazardStatus(this.wire);
  @override
  final String wire;
  static HazardStatus fromWire(String w) => _fromWire(values, w, 'HazardStatus');
}

enum SosStatus implements WireEnum {
  active('ACTIVE'),
  cancelled('CANCELLED'),
  resolved('RESOLVED');

  const SosStatus(this.wire);
  @override
  final String wire;
  static SosStatus fromWire(String w) => _fromWire(values, w, 'SosStatus');
}

enum CrisisStatus implements WireEnum {
  active('ACTIVE'),
  resolved('RESOLVED');

  const CrisisStatus(this.wire);
  @override
  final String wire;
  static CrisisStatus fromWire(String w) => _fromWire(values, w, 'CrisisStatus');
}

enum CrisisTrigger implements WireEnum {
  sos('SOS'),
  mlEmergency('ML_EMERGENCY'),
  hazardCritical('HAZARD_CRITICAL'),
  supervisorEscalation('SUPERVISOR_ESCALATION'),
  manual('MANUAL');

  const CrisisTrigger(this.wire);
  @override
  final String wire;
  static CrisisTrigger fromWire(String w) => _fromWire(values, w, 'CrisisTrigger');
}

enum DecisionAction implements WireEnum {
  confirm('CONFIRM'),
  overrideAction('OVERRIDE'),
  escalate('ESCALATE');

  const DecisionAction(this.wire);
  @override
  final String wire;
  static DecisionAction fromWire(String w) => _fromWire(values, w, 'DecisionAction');
}

enum EscalationLevel implements WireEnum {
  attention('ATTENTION'),
  emergency('EMERGENCY');

  const EscalationLevel(this.wire);
  @override
  final String wire;
  static EscalationLevel fromWire(String w) => _fromWire(values, w, 'EscalationLevel');
}

enum EmergencyType implements WireEnum {
  none('NONE'),
  fire('FIRE'),
  smoke('SMOKE'),
  flooding('FLOODING'),
  roofFall('ROOF_FALL'),
  injuredPerson('INJURED_PERSON'),
  gasOrDustCloud('GAS_OR_DUST_CLOUD'),
  electricalArc('ELECTRICAL_ARC'),
  trappedPerson('TRAPPED_PERSON'),
  other('OTHER');

  const EmergencyType(this.wire);
  @override
  final String wire;
  static EmergencyType fromWire(String w) => _fromWire(values, w, 'EmergencyType');
}

enum RiskBand implements WireEnum {
  green('GREEN'),
  amber('AMBER'),
  red('RED');

  const RiskBand(this.wire);
  @override
  final String wire;
  static RiskBand fromWire(String w) => _fromWire(values, w, 'RiskBand');
}

enum IntegrityFlag implements WireEnum {
  stalePhoto('STALE_PHOTO', 'Photo was taken long before upload'),
  clockSkew('CLOCK_SKEW', 'Phone clock differs from the server'),
  noExif('NO_EXIF', 'Gallery photo has no capture time'),
  duplicateHash('DUPLICATE_HASH', 'This exact photo was seen before'),
  outsideZone('OUTSIDE_ZONE', 'Taken outside the worker\'s zone'),
  lowGpsAccuracy('LOW_GPS_ACCURACY', 'GPS fix was weak or missing'),
  outOfShift('OUT_OF_SHIFT', 'Taken outside the shift window'),
  offlineDelayed('OFFLINE_DELAYED', 'Queued offline before upload'),
  gallerySource('GALLERY_SOURCE', 'Picked from the gallery');

  const IntegrityFlag(this.wire, this.explanation);
  @override
  final String wire;
  final String explanation;
  static IntegrityFlag fromWire(String w) => _fromWire(values, w, 'IntegrityFlag');
}

enum AccountedStatus implements WireEnum {
  safe('SAFE'),
  missing('MISSING'),
  injured('INJURED'),
  unknown('UNKNOWN');

  const AccountedStatus(this.wire);
  @override
  final String wire;
  static AccountedStatus fromWire(String w) => _fromWire(values, w, 'AccountedStatus');
}

enum BroadcastScope implements WireEnum {
  all('ALL'),
  zone('ZONE'),
  role('ROLE');

  const BroadcastScope(this.wire);
  @override
  final String wire;
  static BroadcastScope fromWire(String w) => _fromWire(values, w, 'BroadcastScope');
}

enum BroadcastPriority implements WireEnum {
  info('INFO'),
  urgent('URGENT'),
  emergency('EMERGENCY');

  const BroadcastPriority(this.wire);
  @override
  final String wire;
  static BroadcastPriority fromWire(String w) => _fromWire(values, w, 'BroadcastPriority');
}

enum ContactCategory implements WireEnum {
  police('POLICE', Icons.local_police),
  fire('FIRE', Icons.local_fire_department),
  mineRescue('MINE_RESCUE', Icons.health_and_safety),
  ambulance('AMBULANCE', Icons.emergency),
  districtMiningAuthority('DISTRICT_MINING_AUTHORITY', Icons.account_balance);

  const ContactCategory(this.wire, this.icon);
  @override
  final String wire;
  final IconData icon;
  static ContactCategory fromWire(String w) => _fromWire(values, w, 'ContactCategory');
}

// ---- Add-on pack X (CLAUDE.md section 23, CONTRACT commit X0). Additive only. ----

enum RouteMode implements WireEnum {
  leastHindrance('LEAST_HINDRANCE', 'Least hindrance', 'Fewest obstacles', Icons.verified_user),
  mostLight('MOST_LIGHT', 'Most light', 'Best lit tunnels', Icons.light_mode),
  mostAid('MOST_AID', 'Most help', 'Most tools and aid points', Icons.medical_services),
  direct('DIRECT', 'Direct', 'Shortest distance', Icons.straight);

  const RouteMode(this.wire, this.label, this.hint, this.icon);
  @override
  final String wire;
  final String label;
  final String hint;
  final IconData icon;
  static RouteMode fromWire(String w) => _fromWire(values, w, 'RouteMode');
}

enum AidType implements WireEnum {
  firstAid('FIRST_AID', 'First aid', Icons.medical_services),
  toolStation('TOOL_STATION', 'Tool station', Icons.handyman),
  phone('PHONE', 'Phone', Icons.phone_in_talk),
  scsrCache('SCSR_CACHE', 'Self-rescuer cache', Icons.air),
  fireExtinguisher('FIRE_EXTINGUISHER', 'Extinguisher', Icons.fire_extinguisher);

  const AidType(this.wire, this.label, this.icon);
  @override
  final String wire;
  final String label;
  final IconData icon;
  static AidType fromWire(String w) => _fromWire(values, w, 'AidType');
}

enum PositionSource implements WireEnum {
  gps('GPS'),
  fused('FUSED'),
  pdr('PDR');

  const PositionSource(this.wire);
  @override
  final String wire;
  static PositionSource fromWire(String w) => _fromWire(values, w, 'PositionSource');
}

enum SafetyItemKind implements WireEnum {
  rule('RULE', 'Rule of the day', Icons.gavel),
  react('REACT', 'How to react', Icons.emergency),
  prevent('PREVENT', 'How to prevent', Icons.shield),
  lesson('LESSON', 'Lesson learned', Icons.menu_book);

  const SafetyItemKind(this.wire, this.label, this.icon);
  @override
  final String wire;
  final String label;
  final IconData icon;
  static SafetyItemKind fromWire(String w) => _fromWire(values, w, 'SafetyItemKind');
}

enum VoiceCallStatus implements WireEnum {
  queued('QUEUED', 'Calling…'),
  ringing('RINGING', 'Ringing'),
  inProgress('IN_PROGRESS', 'AI agent speaking'),
  completed('COMPLETED', 'Call ended'),
  failed('FAILED', 'Call failed'),
  dryRun('DRY_RUN', 'Dry run — no real call placed');

  const VoiceCallStatus(this.wire, this.label);
  @override
  final String wire;
  final String label;
  static VoiceCallStatus fromWire(String w) => _fromWire(values, w, 'VoiceCallStatus');
  bool get isFinal => this == completed || this == failed || this == dryRun;
}

enum Presence implements WireEnum {
  live('LIVE'),
  stale('STALE'),
  offline('OFFLINE');

  const Presence(this.wire);
  @override
  final String wire;
  static Presence fromWire(String w) => _fromWire(values, w, 'Presence');
}
