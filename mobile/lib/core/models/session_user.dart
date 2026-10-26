import 'package:equatable/equatable.dart';

import '../../contracts/enums.dart';

class ZoneSupervisor extends Equatable {
  const ZoneSupervisor({required this.name, required this.e164, this.id});
  final String name;
  final String e164;

  /// User id (add-on X5: needed for an AI voice call). Null in profiles cached before X5.
  final String? id;

  factory ZoneSupervisor.fromJson(Map<String, dynamic> j) =>
      ZoneSupervisor(name: j['name'] as String? ?? '', e164: j['e164'] as String? ?? '', id: j['id'] as String?);

  Map<String, dynamic> toJson() => {'name': name, 'e164': e164, 'id': ?id};

  @override
  List<Object?> get props => [name, e164, id];
}

class SessionUser extends Equatable {
  const SessionUser({
    required this.id,
    required this.role,
    required this.fullName,
    required this.employeeId,
    required this.phoneE164,
    this.zoneId,
    this.zoneCode,
    this.zoneName,
    this.evacExitId,
    this.shift,
    this.zoneSupervisors = const [],
  });

  final String id;
  final Role role;
  final String fullName;
  final String employeeId;
  final String phoneE164;
  final String? zoneId;
  final String? zoneCode;
  final String? zoneName;

  /// Layout exit id the admin designated as this zone's emergency exit (null = nearest safe exit).
  final String? evacExitId;
  final Shift? shift;
  final List<ZoneSupervisor> zoneSupervisors;

  String get firstName => fullName.trim().split(' ').first;

  /// Parses the GET /api/auth/me response: { user, zone?, zoneSupervisors? }.
  factory SessionUser.fromMe(Map<String, dynamic> j) {
    final u = j['user'] as Map<String, dynamic>;
    final zone = j['zone'] as Map<String, dynamic>?;
    final phone = u['phone'] as Map<String, dynamic>? ?? const {};
    final sups = (j['zoneSupervisors'] as List?)?.map((e) => ZoneSupervisor.fromJson(e as Map<String, dynamic>)).toList() ?? const <ZoneSupervisor>[];
    final shiftWire = u['shift'] as String?;
    return SessionUser(
      id: (u['id'] ?? u['_id']) as String,
      role: Role.fromWire(u['role'] as String),
      fullName: u['fullName'] as String? ?? '',
      employeeId: u['employeeId'] as String? ?? '',
      phoneE164: phone['e164'] as String? ?? '',
      zoneId: (zone?['id'] ?? u['zoneId'])?.toString(),
      zoneCode: zone?['code'] as String?,
      zoneName: zone?['name'] as String?,
      evacExitId: zone?['evacExitId'] as String?,
      shift: shiftWire == null ? null : Shift.fromWire(shiftWire),
      zoneSupervisors: sups,
    );
  }

  SessionUser copyWith({List<ZoneSupervisor>? zoneSupervisors}) => SessionUser(
        id: id,
        role: role,
        fullName: fullName,
        employeeId: employeeId,
        phoneE164: phoneE164,
        zoneId: zoneId,
        zoneCode: zoneCode,
        zoneName: zoneName,
        evacExitId: evacExitId,
        shift: shift,
        zoneSupervisors: zoneSupervisors ?? this.zoneSupervisors,
      );

  @override
  List<Object?> get props => [id, role, fullName, employeeId, phoneE164, zoneId, zoneCode, zoneName, evacExitId, shift, zoneSupervisors];
}
