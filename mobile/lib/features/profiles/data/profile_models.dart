import 'package:equatable/equatable.dart';

import '../../../contracts/enums.dart';

/// Access level the server used for this profile (CLAUDE.md section 23.2).
enum ProfileLevel { full, self, crew }

ProfileLevel _level(Object? v) => switch (v) { 'full' => ProfileLevel.full, 'self' => ProfileLevel.self, _ => ProfileLevel.crew };
int? _int(Object? v) => (v as num?)?.toInt();
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
T? _enum<T>(T Function(String) f, Object? v) {
  if (v is! String) return null;
  try {
    return f(v);
  } catch (_) {
    return null;
  }
}

class ZoneRef extends Equatable {
  const ZoneRef({required this.id, required this.code, required this.name});
  final String id, code, name;
  static ZoneRef? fromJson(Object? j) {
    final m = _map(j);
    if (m.isEmpty) return null;
    return ZoneRef(id: '${m['id']}', code: m['code'] as String? ?? '', name: m['name'] as String? ?? '');
  }

  @override
  List<Object?> get props => [id, code];
}

class ProfilePhoto extends Equatable {
  const ProfilePhoto({this.url, this.at, this.checkInId});
  final String? url;
  final DateTime? at;
  final String? checkInId;
  static ProfilePhoto? fromJson(Object? j) {
    final m = _map(j);
    if (m.isEmpty) return null;
    return ProfilePhoto(url: m['url'] as String?, at: _date(m['at']), checkInId: m['checkInId'] as String?);
  }

  @override
  List<Object?> get props => [url, at, checkInId];
}

class TodayStatus extends Equatable {
  const TodayStatus({required this.status, this.verdict});
  final String status;
  final Verdict? verdict;
  static TodayStatus? fromJson(Object? j) {
    final m = _map(j);
    if (m.isEmpty) return null;
    return TodayStatus(status: m['status'] as String? ?? 'NOT_CHECKED_IN', verdict: _enum(Verdict.fromWire, m['verdict']));
  }

  bool get checkedIn => status != 'NOT_CHECKED_IN';
  @override
  List<Object?> get props => [status, verdict];
}

/// One card in a profile list.
class ProfileCard extends Equatable {
  const ProfileCard({
    required this.id,
    required this.fullName,
    required this.employeeId,
    required this.role,
    required this.level,
    this.status = 'active',
    this.shift,
    this.zone,
    this.designation,
    this.photo,
    this.today,
    this.score,
    this.streak,
    this.xp,
    this.badges,
    this.rank,
    this.riskBand,
    this.presence,
  });

  final String id, fullName, employeeId, status;
  final Role role;
  final ProfileLevel level;
  final Shift? shift;
  final ZoneRef? zone;
  final String? designation;
  final ProfilePhoto? photo;
  final TodayStatus? today;
  final int? score, streak, xp, badges, rank;
  final RiskBand? riskBand;
  final Presence? presence;

  bool get active => status == 'active';

  factory ProfileCard.fromJson(Map<String, dynamic> j) {
    final s = _map(j['score']);
    return ProfileCard(
      id: '${j['id']}',
      fullName: j['fullName'] as String? ?? '',
      employeeId: j['employeeId'] as String? ?? '',
      role: _enum(Role.fromWire, j['role']) ?? Role.miner,
      level: _level(j['level']),
      status: j['status'] as String? ?? 'active',
      shift: _enum(Shift.fromWire, j['shift']),
      zone: ZoneRef.fromJson(j['zone']),
      designation: j['designation'] as String?,
      photo: ProfilePhoto.fromJson(j['photo']),
      today: TodayStatus.fromJson(j['today']),
      score: _int(s['score']),
      streak: _int(s['streak']),
      xp: _int(s['xp']),
      badges: s['badges'] is List ? (s['badges'] as List).length : _int(s['badges']),
      rank: _int(s['rank']),
      riskBand: _enum(RiskBand.fromWire, j['riskBand']),
      presence: _enum(Presence.fromWire, j['presence']),
    );
  }

  /// The card a fresh detail fetch implies (used to update one card after `profile:updated`).
  factory ProfileCard.fromDetail(ProfileDetail d) => ProfileCard(
        id: d.id,
        fullName: d.fullName,
        employeeId: d.employeeId,
        role: d.role,
        level: d.level,
        status: d.status,
        shift: d.shift,
        zone: d.zone,
        designation: d.designation,
        photo: d.photo,
        today: d.today,
        score: d.score?.score,
        streak: d.score?.streak,
        xp: d.score?.xp,
        badges: d.score?.badges.length,
        rank: d.score?.rank,
        riskBand: d.score?.riskBand,
        presence: d.presence?.presence,
      );

  ProfileCard withPresence(Presence p) => ProfileCard(
        id: id, fullName: fullName, employeeId: employeeId, role: role, level: level, status: status, shift: shift, zone: zone, designation: designation,
        photo: photo, today: today, score: score, streak: streak, xp: xp, badges: badges, rank: rank, riskBand: riskBand, presence: p,
      );

  @override
  List<Object?> get props => [id, fullName, employeeId, role, level, status, shift, zone, designation, photo, today, score, streak, xp, badges, rank, riskBand, presence];
}

class CalendarDay extends Equatable {
  const CalendarDay({required this.day, this.verdict, this.decided = false});
  final String day;
  final Verdict? verdict;
  final bool decided;
  @override
  List<Object?> get props => [day, verdict, decided];
}

class ScoreInfo extends Equatable {
  const ScoreInfo({this.score, this.streak = 0, this.xp = 0, this.badges = const [], this.rank, this.rankOf, this.riskBand, this.history = const []});
  final int? score, rank, rankOf;
  final int streak, xp;
  final List<String> badges;
  final RiskBand? riskBand;
  final List<(String, int)> history;

  static ScoreInfo? fromJson(Object? j) {
    final m = _map(j);
    if (m.isEmpty) return null;
    return ScoreInfo(
      score: _int(m['score']),
      streak: _int(m['streak']) ?? 0,
      xp: _int(m['xp']) ?? 0,
      badges: ((m['badges'] as List?) ?? const []).map((b) => b is Map ? '${b['key']}' : '$b').toList(),
      rank: _int(m['rank']),
      rankOf: _int(m['rankOf']),
      riskBand: _enum(RiskBand.fromWire, m['riskBand']),
      history: ((m['history'] as List?) ?? const []).map((h) => ('${(h as Map)['day']}', _int(h['score']) ?? 0)).toList(),
    );
  }

  @override
  List<Object?> get props => [score, streak, xp, badges, rank, rankOf, riskBand, history];
}

class Certification extends Equatable {
  const Certification({required this.name, this.issuedAt, this.expiresAt, this.expired = false});
  final String name;
  final DateTime? issuedAt, expiresAt;
  final bool expired;
  Map<String, dynamic> toJson() => {'name': name, if (issuedAt != null) 'issuedAt': issuedAt!.toUtc().toIso8601String(), if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String()};
  @override
  List<Object?> get props => [name, issuedAt, expiresAt, expired];
}

class HazardLine extends Equatable {
  const HazardLine({required this.id, required this.category, required this.status, this.severity, this.createdAt});
  final String id, category, status;
  final String? severity;
  final DateTime? createdAt;
  @override
  List<Object?> get props => [id, status];
}

class PresenceInfo extends Equatable {
  const PresenceInfo({required this.presence, this.lat, this.lng, this.accuracyM, this.source, this.tunnelId, this.ts});
  final Presence presence;
  final double? lat, lng, accuracyM;
  final PositionSource? source;
  final String? tunnelId;
  final DateTime? ts;
  static PresenceInfo? fromJson(Object? j) {
    final m = _map(j);
    final p = _enum(Presence.fromWire, m['presence']);
    if (p == null) return null;
    return PresenceInfo(
      presence: p,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      accuracyM: (m['accuracyM'] as num?)?.toDouble(),
      source: _enum(PositionSource.fromWire, m['source']),
      tunnelId: m['tunnelId'] as String?,
      ts: _date(m['ts']),
    );
  }

  @override
  List<Object?> get props => [presence, lat, lng, source, tunnelId, ts];
}

class SupervisorStats extends Equatable {
  const SupervisorStats({required this.decided30d, required this.onTime, required this.breaches, required this.pending, required this.teamSize, this.reliability});
  final int decided30d, onTime, breaches, pending, teamSize;
  final int? reliability;
  static SupervisorStats? fromJson(Object? j) {
    final m = _map(j);
    if (m.isEmpty) return null;
    return SupervisorStats(decided30d: _int(m['decided30d']) ?? 0, onTime: _int(m['onTime']) ?? 0, breaches: _int(m['breaches']) ?? 0, pending: _int(m['pending']) ?? 0, teamSize: _int(m['teamSize']) ?? 0, reliability: _int(m['reliability']));
  }

  @override
  List<Object?> get props => [decided30d, onTime, breaches, pending, teamSize, reliability];
}

/// Full (or trimmed) profile from GET /api/profiles/:userId. Fields the viewer may not see are null / empty.
class ProfileDetail extends Equatable {
  const ProfileDetail({
    required this.id,
    required this.fullName,
    required this.employeeId,
    required this.role,
    required this.level,
    this.status = 'active',
    this.shift,
    this.zone,
    this.email,
    this.phoneMasked,
    this.phoneE164,
    this.hasPhone = false,
    this.joinedAt,
    this.designation,
    this.experienceYears,
    this.bloodGroup,
    this.medicalNotes,
    this.certifications = const [],
    this.expiring = const [],
    this.photo,
    this.requiredPpe = const [],
    this.today,
    this.calendar = const [],
    this.score,
    this.rewards = const [],
    this.hazardCounts = const {},
    this.hazards = const [],
    this.sosCount = 0,
    this.supervisorStats,
    this.crisisAccounted,
    this.presence,
  });

  final String id, fullName, employeeId, status;
  final Role role;
  final ProfileLevel level;
  final Shift? shift;
  final ZoneRef? zone;
  final String? email, phoneMasked, phoneE164, designation, bloodGroup, medicalNotes;
  final bool hasPhone;
  final DateTime? joinedAt;
  final int? experienceYears;
  final List<Certification> certifications, expiring;
  final ProfilePhoto? photo;
  final List<PpeKey> requiredPpe;
  final TodayStatus? today;
  final List<CalendarDay> calendar;
  final ScoreInfo? score;
  final List<String> rewards;
  final Map<String, int> hazardCounts;
  final List<HazardLine> hazards;
  final int sosCount;
  final SupervisorStats? supervisorStats;
  final String? crisisAccounted;
  final PresenceInfo? presence;

  bool get isCrew => level == ProfileLevel.crew;

  factory ProfileDetail.fromJson(Map<String, dynamic> j) {
    Certification cert(Object? x) {
      final m = _map(x);
      return Certification(name: m['name'] as String? ?? '', issuedAt: _date(m['issuedAt']), expiresAt: _date(m['expiresAt']), expired: m['expired'] == true);
    }

    final hz = _map(j['hazards']);
    return ProfileDetail(
      id: '${j['id']}',
      fullName: j['fullName'] as String? ?? '',
      employeeId: j['employeeId'] as String? ?? '',
      role: _enum(Role.fromWire, j['role']) ?? Role.miner,
      level: _level(j['level']),
      status: j['status'] as String? ?? 'active',
      shift: _enum(Shift.fromWire, j['shift']),
      zone: ZoneRef.fromJson(j['zone']),
      email: j['email'] as String?,
      phoneMasked: j['phoneMasked'] as String?,
      phoneE164: j['phoneE164'] as String?,
      hasPhone: j['hasPhone'] == true,
      joinedAt: _date(j['joinedAt']),
      designation: j['designation'] as String?,
      experienceYears: _int(j['experienceYears']),
      bloodGroup: j['bloodGroup'] as String?,
      medicalNotes: j['medicalNotes'] as String?,
      certifications: ((j['certifications'] as List?) ?? const []).map(cert).toList(),
      expiring: ((j['certificationsExpiring'] as List?) ?? const []).map(cert).toList(),
      photo: ProfilePhoto.fromJson(j['photo']),
      requiredPpe: ((j['requiredPpe'] as List?) ?? const []).map((k) => _enum(PpeKey.fromWire, k)).whereType<PpeKey>().toList(),
      today: TodayStatus.fromJson(j['today']),
      calendar: ((j['calendar'] as List?) ?? const []).map((d) {
        final m = _map(d);
        return CalendarDay(day: m['day'] as String? ?? '', verdict: _enum(Verdict.fromWire, m['verdict']), decided: m['decided'] == true);
      }).toList(),
      score: ScoreInfo.fromJson(j['score']),
      rewards: ((j['rewards'] as List?) ?? const []).map((r) => (_map(r)['title'] ?? _map(r)['key'] ?? '').toString()).where((s) => s.isNotEmpty).toList(),
      hazardCounts: _map(hz['counts']).map((k, v) => MapEntry(k, _int(v) ?? 0)),
      hazards: ((hz['recent'] as List?) ?? const []).map((h) {
        final m = _map(h);
        return HazardLine(id: '${m['id']}', category: m['category'] as String? ?? 'OTHER', status: m['status'] as String? ?? 'OPEN', severity: m['severity'] as String?, createdAt: _date(m['createdAt']));
      }).toList(),
      sosCount: _int(_map(j['sos'])['count']) ?? 0,
      supervisorStats: SupervisorStats.fromJson(j['supervisorStats']),
      crisisAccounted: _map(j['crisis'])['accounted'] as String?,
      presence: PresenceInfo.fromJson(j['presence']),
    );
  }

  @override
  List<Object?> get props => [id, fullName, employeeId, role, level, status, shift, zone, email, phoneMasked, designation, experienceYears, bloodGroup, medicalNotes, certifications, photo, today, calendar, score, hazardCounts, hazards, sosCount, supervisorStats, crisisAccounted, presence];
}
