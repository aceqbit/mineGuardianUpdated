import '../../../contracts/enums.dart';
import '../../../core/api/api_client.dart';
import '../../../core/db/cache_repository.dart';
import '../../../core/db/layout_repository.dart';
import '../../../core/models/mine_layout.dart';
import '../../../core/models/sample_layout.dart';
import 'route_modes.dart';

/// One position on the map (fused from the phone, or a tracked person from the server).
class MapFix {
  const MapFix({required this.lat, required this.lng, required this.accuracyM, required this.ts, this.source = PositionSource.gps, this.headingDeg, this.speedMps, this.tunnelId});
  final double lat, lng, accuracyM;
  final DateTime ts;
  final PositionSource source;
  final double? headingDeg, speedMps;
  final String? tunnelId;
  GeoPoint get point => GeoPoint(lat, lng);
}

/// A tracked person on the admin / supervisor live map (`tracking:positions`, `GET /api/tracking/live`).
class FleetPosition {
  const FleetPosition({required this.userId, required this.name, required this.employeeId, required this.role, required this.zoneId, required this.fix, required this.presence, this.sosId});
  final String userId, name, employeeId;
  final Role role;
  final String? zoneId;
  final MapFix fix;
  final Presence presence;
  final String? sosId;

  static FleetPosition? fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble(), lng = (j['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    T? e<T>(T Function(String) f, Object? v) {
      try {
        return v is String ? f(v) : null;
      } catch (_) {
        return null;
      }
    }

    return FleetPosition(
      userId: '${j['userId']}',
      name: j['name'] as String? ?? '',
      employeeId: j['employeeId'] as String? ?? '',
      role: e(Role.fromWire, j['role']) ?? Role.miner,
      zoneId: j['zoneId'] as String?,
      presence: e(Presence.fromWire, j['presence']) ?? Presence.offline,
      sosId: j['sosId'] as String?,
      fix: MapFix(
        lat: lat,
        lng: lng,
        accuracyM: (j['accuracyM'] as num?)?.toDouble() ?? 0,
        ts: DateTime.tryParse('${j['ts']}')?.toUtc() ?? DateTime.now().toUtc(),
        source: e(PositionSource.fromWire, j['source']) ?? PositionSource.gps,
        headingDeg: (j['headingDeg'] as num?)?.toDouble(),
        speedMps: (j['speedMps'] as num?)?.toDouble(),
        tunnelId: j['tunnelId'] as String?,
      ),
    );
  }
}

class LiveMapRepository {
  LiveMapRepository({required ApiClient api, required CacheRepository cache})
      : _api = api,
        _layouts = LayoutRepository(api: api, cache: cache);
  final ApiClient _api;
  final LayoutRepository _layouts;

  /// The real mine layout (cached for offline). Never the built-in sample: the live map is not a demo map.
  Future<MineLayoutData?> layout() async {
    final l = await _layouts.refresh();
    return l == null || l.version == sampleLayoutVersion ? null : l;
  }

  /// Active hazards to route around. Offline: the cached open hazards.
  Future<List<RouteHazard>> hazards() async {
    try {
      final j = await _api.getJson('/api/tracking/hazards');
      final rows = ((j['hazards'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
      await _layouts.cacheOpenHazards(rows);
      return rows.map(RouteHazard.fromJson).whereType<RouteHazard>().toList();
    } on ApiException {
      return (await _layouts.cachedOpenHazards()).map(RouteHazard.fromJson).whereType<RouteHazard>().toList();
    }
  }

  /// Zone id -> code (GET /api/zones is public).
  Future<Map<String, String>> zones() async {
    try {
      final rows = await _api.getList('/api/zones');
      return {for (final z in rows) '${(z as Map)['id'] ?? z['_id']}': '${z['code']}'};
    } on ApiException {
      return const {};
    }
  }

  Future<List<FleetPosition>> fleet({String? zoneId}) async {
    final j = await _api.getJson('/api/tracking/live', query: {'zoneId': ?zoneId});
    return ((j['positions'] as List?) ?? const []).map((e) => FleetPosition.fromJson((e as Map).cast<String, dynamic>())).whereType<FleetPosition>().toList();
  }
}
