import 'package:equatable/equatable.dart';

import '../../../core/api/api_client.dart';

class SupervisorRef extends Equatable {
  const SupervisorRef({required this.id, required this.fullName, this.phoneMasked = '', this.zoneId});
  final String id;
  final String fullName;
  final String phoneMasked;
  final String? zoneId;

  factory SupervisorRef.fromJson(Map<String, dynamic> j) => SupervisorRef(id: j['id'].toString(), fullName: j['fullName'] as String? ?? '', phoneMasked: j['phoneMasked'] as String? ?? '', zoneId: j['zoneId']?.toString());

  @override
  List<Object?> get props => [id, fullName, phoneMasked, zoneId];
}

class ZoneOverview extends Equatable {
  const ZoneOverview({required this.id, required this.code, required this.name, required this.supervisors, required this.minersCount, required this.checkedInToday, this.evacExitId});
  final String id;
  final String code;
  final String name;
  final List<SupervisorRef> supervisors;
  final int minersCount;
  final int checkedInToday;

  /// Layout exit id the admin designated as this zone's emergency exit; null = nearest safe exit.
  final String? evacExitId;

  factory ZoneOverview.fromJson(Map<String, dynamic> j) => ZoneOverview(
        id: j['id'].toString(),
        code: j['code'] as String? ?? '',
        name: j['name'] as String? ?? '',
        supervisors: ((j['supervisors'] as List?) ?? const []).map((e) => SupervisorRef.fromJson((e as Map).cast<String, dynamic>())).toList(),
        minersCount: (j['minersCount'] as num?)?.toInt() ?? 0,
        checkedInToday: (j['checkedInToday'] as num?)?.toInt() ?? 0,
        evacExitId: j['evacExitId'] as String?,
      );

  @override
  List<Object?> get props => [id, code, name, supervisors, minersCount, checkedInToday, evacExitId];
}

/// An exit from the mine layout, for the admin's emergency-exit picker.
class ExitRef extends Equatable {
  const ExitRef({required this.id, required this.name, required this.exitType});
  final String id;
  final String name;
  final String exitType;
  @override
  List<Object?> get props => [id, name, exitType];
}

class ActiveCrisisRef extends Equatable {
  const ActiveCrisisRef({required this.id, required this.startedAt, required this.trigger});
  final String id;
  final DateTime startedAt;
  final String trigger;
  @override
  List<Object?> get props => [id, startedAt, trigger];
}

class AdminOverview extends Equatable {
  const AdminOverview({required this.workers, required this.supervisors, required this.zoneCount, required this.openHazards, required this.compliancePct, required this.pendingReviews, required this.crisis, required this.zones});
  final int workers;
  final int supervisors;
  final int zoneCount;
  final int openHazards;
  final int? compliancePct;
  final int? pendingReviews;
  final ActiveCrisisRef? crisis;
  final List<ZoneOverview> zones;

  factory AdminOverview.fromJson(Map<String, dynamic> j) {
    final counts = (j['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
    final c = (j['activeCrisis'] as Map?)?.cast<String, dynamic>();
    final trig = c?['trigger'];
    return AdminOverview(
      workers: (counts['workers'] as num?)?.toInt() ?? 0,
      supervisors: (counts['supervisors'] as num?)?.toInt() ?? 0,
      zoneCount: (counts['zones'] as num?)?.toInt() ?? 0,
      openHazards: (j['openHazards'] as num?)?.toInt() ?? 0,
      compliancePct: (j['todayCompliancePct'] as num?)?.toInt(),
      pendingReviews: (j['pendingReviews'] as num?)?.toInt(),
      crisis: c == null ? null : ActiveCrisisRef(id: c['id'].toString(), startedAt: DateTime.tryParse('${c['startedAt']}')?.toUtc() ?? DateTime.now().toUtc(), trigger: trig is Map ? (trig['type'] ?? '').toString() : (trig ?? '').toString()),
      zones: ((j['zones'] as List?) ?? const []).map((e) => ZoneOverview.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }

  @override
  List<Object?> get props => [workers, supervisors, zoneCount, openHazards, compliancePct, pendingReviews, crisis, zones];
}

class AdminRepository {
  AdminRepository({required ApiClient api}) : _api = api;
  final ApiClient _api;

  Future<AdminOverview> overview() async => AdminOverview.fromJson(await _api.getJson('/api/admin/overview'));

  Future<List<SupervisorRef>> supervisors() async => (await _api.getList('/api/admin/supervisors')).map((e) => SupervisorRef.fromJson((e as Map).cast<String, dynamic>())).toList();

  Future<void> setZoneSupervisors(String zoneId, List<String> ids) => _api.putJson('/api/zones/$zoneId/supervisors', body: {'supervisorIds': ids});

  /// Exits from the latest layout (the same ids the server validates against).
  Future<List<ExitRef>> exits() async {
    final json = await _api.getJson('/api/layout');
    final feats = ((json['geojson'] as Map?)?['features'] as List?) ?? const [];
    return [
      for (final f in feats)
        if (((f as Map)['properties'] as Map?)?['kind'] == 'exit')
          ExitRef(id: (f['properties'] as Map)['id'].toString(), name: (f['properties'] as Map)['name'] as String? ?? (f['properties'] as Map)['id'].toString(), exitType: (f['properties'] as Map)['exitType'] as String? ?? 'shaft'),
    ];
  }

  /// null clears the choice (nearest safe exit).
  Future<void> setZoneEvacExit(String zoneId, String? exitId) => _api.putJson('/api/zones/$zoneId/evac-exit', body: {'exitId': exitId});
}
