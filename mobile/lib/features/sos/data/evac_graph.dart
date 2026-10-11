import 'dart:math' as math;

import '../../../core/models/mine_layout.dart';

/// Walking speed used for ETA (m/s).
const double walkSpeedMps = 1.1;

/// Hazard categories that make nearby tunnels unusable for the offline route.
const _blockingCategories = {'FIRE_SMOKE', 'FLOODING', 'ROOF_FALL'};
const double hazardAvoidRadiusM = 25;

class CachedHazard {
  const CachedHazard({required this.point, required this.category, this.severity});
  final GeoPoint point;
  final String category;
  final String? severity;

  bool get blocking => severity == 'CRITICAL' || _blockingCategories.contains(category);

  static CachedHazard? fromJson(Map<String, dynamic> j) {
    final loc = (j['locationLatLng'] ?? j['location']) as Map?;
    double? lat, lng;
    if (loc != null && loc['lat'] != null) {
      lat = (loc['lat'] as num).toDouble();
      lng = (loc['lng'] as num).toDouble();
    } else if (loc != null && loc['coordinates'] is List) {
      lng = ((loc['coordinates'] as List)[0] as num).toDouble();
      lat = ((loc['coordinates'] as List)[1] as num).toDouble();
    }
    if (lat == null || lng == null) return null;
    final ai = j['ai'] as Map?;
    return CachedHazard(point: GeoPoint(lat, lng), category: j['category'] as String? ?? 'OTHER', severity: ai?['severity'] as String?);
  }
}

class EvacRoute {
  const EvacRoute({required this.exit, required this.nodes, required this.points, required this.distanceM, this.tunnelIds = const [], this.tunnelLengths = const []});
  final LayoutExit exit;
  final List<String> nodes;
  final List<GeoPoint> points;
  final double distanceM;

  /// Tunnel ids walked, in order, with their lengths (used for overlap between alternatives).
  final List<String> tunnelIds;
  final List<double> tunnelLengths;

  /// Identifies this exact path (several routes can lead to the same exit).
  String get key => '${exit.id}|${tunnelIds.join(',')}';

  double get etaSec => distanceM / walkSpeedMps;
  int get etaMin => math.max(1, (etaSec / 60).ceil());
  String get summary => 'Go to ${exit.name} · ${distanceM.round()} m · ~$etaMin min';
}

double distToSegmentM(GeoPoint p, GeoPoint a, GeoPoint b) {
  // local equirectangular projection around p
  final k = 111320.0;
  final cosLat = math.cos(p.lat * math.pi / 180);
  double x(GeoPoint q) => (q.lng - p.lng) * k * cosLat;
  double y(GeoPoint q) => (q.lat - p.lat) * k;
  final ax = x(a), ay = y(a), bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (((-ax) * dx + (-ay) * dy) / len2).clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt(cx * cx + cy * cy);
}

class EvacGraph {
  EvacGraph._(this.layout, this._adj, this._nodePoint, this.skipped);

  final MineLayoutData layout;
  final Map<String, List<(String, double, String)>> _adj; // node -> (neighbour, lengthM, tunnelId)
  final Map<String, GeoPoint> _nodePoint;

  /// Tunnel ids left out of the graph (blocked or near a dangerous cached hazard).
  final Set<String> skipped;

  /// Builds the graph. Tunnels that are blocked, or lie within 25 m of a cached CRITICAL / FIRE_SMOKE / FLOODING / ROOF_FALL hazard, are skipped.
  factory EvacGraph.build(MineLayoutData layout, {List<CachedHazard> hazards = const [], Set<String> extraBlocked = const {}}) {
    final adj = <String, List<(String, double, String)>>{};
    final pts = {for (final j in layout.junctions) j.id: j.point};
    for (final j in layout.junctions) {
      adj[j.id] = [];
    }
    final skipped = <String>{};
    final dangerous = hazards.where((h) => h.blocking).toList();
    for (final t in layout.tunnels) {
      var bad = t.blocked || extraBlocked.contains(t.id);
      if (!bad) {
        for (final h in dangerous) {
          for (var i = 1; i < t.coords.length; i++) {
            if (distToSegmentM(h.point, t.coords[i - 1], t.coords[i]) <= hazardAvoidRadiusM) {
              bad = true;
              break;
            }
          }
          if (bad) break;
        }
      }
      if (bad) {
        skipped.add(t.id);
        continue;
      }
      final len = t.lengthM;
      adj.putIfAbsent(t.from, () => []).add((t.to, len, t.id));
      adj.putIfAbsent(t.to, () => []).add((t.from, len, t.id));
    }
    return EvacGraph._(layout, adj, pts, skipped);
  }

  /// Nearest junction id to a point.
  String? nearestJunction(GeoPoint p) {
    String? best;
    var bestD = double.infinity;
    for (final e in _nodePoint.entries) {
      final d = haversineM(p, e.value);
      if (d < bestD) {
        bestD = d;
        best = e.key;
      }
    }
    return best;
  }

  /// Dijkstra from [start]. [penalty] multiplies the cost of named tunnels (used to find alternatives).
  ({Map<String, double> dist, Map<String, String> prev, Map<String, (double, String)> via}) _search(String start, Map<String, double> penalty) {
    final dist = <String, double>{start: 0};
    final prev = <String, String>{};
    final via = <String, (double, String)>{}; // node -> (real length, tunnelId) of the edge used to reach it
    final done = <String>{};
    final open = <String>{start};
    while (open.isNotEmpty) {
      final u = open.reduce((a, b) => (dist[a] ?? double.infinity) <= (dist[b] ?? double.infinity) ? a : b);
      open.remove(u);
      if (!done.add(u)) continue;
      for (final (v, w, id) in _adj[u] ?? const <(String, double, String)>[]) {
        final nd = dist[u]! + w * (penalty[id] ?? 1.0);
        if (nd < (dist[v] ?? double.infinity)) {
          dist[v] = nd;
          prev[v] = u;
          via[v] = (w, id);
          open.add(v);
        }
      }
    }
    return (dist: dist, prev: prev, via: via);
  }

  EvacRoute _routeTo(LayoutExit ex, String start, ({Map<String, double> dist, Map<String, String> prev, Map<String, (double, String)> via}) s) {
    final nodes = <String>[ex.node];
    final ids = <String>[];
    final lens = <double>[];
    var real = 0.0;
    while (nodes.first != start) {
      final v = nodes.first;
      final (len, id) = s.via[v]!;
      ids.insert(0, id);
      lens.insert(0, len);
      real += len;
      nodes.insert(0, s.prev[v]!);
    }
    return EvacRoute(exit: ex, nodes: nodes, points: [for (final n in nodes) _nodePoint[n]!], distanceM: real, tunnelIds: ids, tunnelLengths: lens);
  }

  /// Dijkstra from [start] to every exit; returns the shortest reachable route, or null.
  EvacRoute? shortestToExit(String start) {
    final s = _search(start, const {});
    LayoutExit? bestExit;
    var bestD = double.infinity;
    for (final ex in layout.exits) {
      final d = s.dist[ex.node];
      if (d != null && d < bestD) {
        bestD = d;
        bestExit = ex;
      }
    }
    return bestExit == null ? null : _routeTo(bestExit, start, s);
  }

  /// Share (0..1) of [a]'s length that [b] also walks.
  static double overlap(EvacRoute a, EvacRoute b) {
    if (a.distanceM <= 0) return 0;
    final inB = b.tunnelIds.toSet();
    var shared = 0.0;
    for (var i = 0; i < a.tunnelIds.length; i++) {
      if (inB.contains(a.tunnelIds[i])) shared += a.tunnelLengths[i];
    }
    return shared / a.distanceM;
  }

  /// Up to [k] distinct routes to exits, best first. Each next candidate is searched with the tunnels already used made
  /// costlier, then accepted only if it shares at most [maxOverlap] of its length with every accepted route.
  List<EvacRoute> alternativeRoutes(String start, {int k = 3, double maxOverlap = 0.7}) {
    final accepted = <EvacRoute>[];
    final penalty = <String, double>{};
    for (var round = 0; round < k * 3 && accepted.length < k; round++) {
      final s = _search(start, penalty);
      final cands = <EvacRoute>[];
      for (final ex in layout.exits) {
        if (s.dist.containsKey(ex.node)) cands.add(_routeTo(ex, start, s));
      }
      cands.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      var added = false;
      for (final c in cands) {
        final dup = accepted.any((r) => r.exit.id == c.exit.id); // one route per exit keeps the choice clear
        if (!dup && accepted.every((r) => overlap(c, r) <= maxOverlap)) {
          accepted.add(c);
          added = true;
          break;
        }
      }
      // Make everything walked so far costlier so the next search prefers a different way out.
      for (final r in (added ? [accepted.last] : cands.take(1))) {
        for (final id in r.tunnelIds) {
          penalty[id] = (penalty[id] ?? 1.0) * 2.5;
        }
      }
    }
    accepted.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return accepted;
  }

  /// Where a worker can be sent: every exit and every refuge chamber (a refuge is listed with exitType 'refuge').
  List<LayoutExit> get destinations => [
        ...layout.exits,
        for (final r in layout.refuges) LayoutExit(id: r.id, name: r.name, exitType: 'refuge', point: r.point, node: r.node),
      ];

  LayoutExit? destination(String id) => destinations.where((d) => d.id == id).firstOrNull;

  /// Up to [k] distinct routes from [start] to one place, best first. Each next search makes the tunnels already used
  /// costlier; a route is kept only if it shares at most [maxOverlap] of its length with every route kept so far.
  List<EvacRoute> routesBetween(String start, LayoutExit dest, {int k = 4, double maxOverlap = 0.7}) {
    final accepted = <EvacRoute>[];
    final penalty = <String, double>{};
    for (var round = 0; round < k * 3 && accepted.length < k; round++) {
      final s = _search(start, penalty);
      if (!s.dist.containsKey(dest.node)) break;
      final r = _routeTo(dest, start, s);
      if (!accepted.any((a) => a.key == r.key) && accepted.every((a) => overlap(r, a) <= maxOverlap)) accepted.add(r);
      if (r.tunnelIds.isEmpty) break; // start is the destination
      for (final id in r.tunnelIds) {
        penalty[id] = (penalty[id] ?? 1.0) * 2.5;
      }
    }
    accepted.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return accepted;
  }

  /// Shortest distance in metres from [p] to the polyline of [route].
  static double distanceToRouteM(GeoPoint p, EvacRoute route) {
    var best = double.infinity;
    for (var i = 1; i < route.points.length; i++) {
      best = math.min(best, distToSegmentM(p, route.points[i - 1], route.points[i]));
    }
    return best;
  }

  /// Alternatives from a GPS position (snapped to the nearest junction).
  List<EvacRoute> alternativesFrom(GeoPoint position, {int k = 3}) {
    final n = nearestJunction(position);
    return n == null ? const [] : alternativeRoutes(n, k: k);
  }

  /// Shortest route from [start] to one named exit, or null when it is blocked / unreachable.
  EvacRoute? routeToExit(String start, String exitId) {
    final ex = layout.exits.where((e) => e.id == exitId).firstOrNull;
    if (ex == null) return null;
    final s = _search(start, const {});
    return s.dist.containsKey(ex.node) ? _routeTo(ex, start, s) : null;
  }

  /// Route from a GPS position (snapped to the nearest junction).
  EvacRoute? routeFrom(GeoPoint position) {
    final n = nearestJunction(position);
    return n == null ? null : shortestToExit(n);
  }

  /// With no position: from the junction nearest the zone centroid.
  EvacRoute? routeFromZone(String zoneCode) {
    final zone = layout.zones.where((z) => z.code == zoneCode).firstOrNull;
    if (zone == null) return null;
    final ring = zone.ring;
    final lat = ring.map((p) => p.lat).reduce((a, b) => a + b) / ring.length;
    final lng = ring.map((p) => p.lng).reduce((a, b) => a + b) / ring.length;
    return routeFrom(GeoPoint(lat, lng));
  }
}
