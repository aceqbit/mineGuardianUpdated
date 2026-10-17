import 'dart:math' as math;

import '../../../contracts/enums.dart';
import '../../../core/models/mine_layout.dart';
import '../../sos/data/evac_graph.dart';

/// Walking speed for ETAs when the live speed is unknown (CLAUDE.md section 8).
const double defaultWalkMps = 1.1;

/// Hazard categories that close nearby tunnels even before the AI has classified them (same rule as the rerouter).
const _closingCategories = {'FIRE_SMOKE', 'FLOODING', 'ROOF_FALL', 'GAS_LEAK'};
const double hardHazardRadiusM = 15;
const double softHazardRadiusM = 60;
const double aidRadiusM = 20;
const double litLux = 50;

class RouteHazard {
  const RouteHazard({required this.point, required this.category, this.severity});
  final GeoPoint point;
  final String category;
  final String? severity;

  /// ACTIVE CRITICAL, or an unclassified hazard of a closing category.
  bool get closesTunnels => severity == 'CRITICAL' || (severity == null && _closingCategories.contains(category));

  /// Soft proximity weight (LOW 0.3, MEDIUM 0.8, CRITICAL 2.0; unclassified counts as MEDIUM).
  double get weight => switch (severity) { 'LOW' => 0.3, 'CRITICAL' => 2.0, _ => 0.8 };

  static RouteHazard? fromJson(Map<String, dynamic> j) {
    final c = CachedHazard.fromJson(j);
    if (c == null) return null;
    return RouteHazard(point: c.point, category: c.category, severity: (j['severity'] as String?) ?? c.severity);
  }
}

enum TargetKind { exit, refuge, aid, junction }

/// A place the worker can route to.
class RouteTarget {
  const RouteTarget({required this.id, required this.name, required this.kind, required this.point, required this.node, this.aidType});
  final String id;
  final String name;
  final TargetKind kind;
  final GeoPoint point;
  final String node;
  final String? aidType;

  LayoutExit get asExit => LayoutExit(id: id, name: name, exitType: kind.name, point: point, node: node);
}

/// One computed route. Several modes can share it (then [modes] has all of them).
class ModeRoute {
  const ModeRoute({required this.modes, required this.target, required this.nodes, required this.points, required this.tunnelIds, required this.tunnelLengths, required this.distanceM, required this.litPct, required this.aidsPassed, required this.hazardsNear, required this.cost});
  final Set<RouteMode> modes;
  final RouteTarget target;
  final List<String> nodes;
  final List<GeoPoint> points;
  final List<String> tunnelIds;
  final List<double> tunnelLengths;
  final double distanceM;

  /// Share of the route (by length) in tunnels lit to at least [litLux].
  final double litPct;
  final List<LayoutAid> aidsPassed;

  /// Hazards within [softHazardRadiusM] of the route.
  final int hazardsNear;

  /// Cost in the first mode's own units (for tests and tie-breaks).
  final double cost;

  String get key => tunnelIds.join(',');
  RouteMode get primary => RouteMode.values.firstWhere(modes.contains);
  double etaSec([double? speedMps]) => distanceM / ((speedMps != null && speedMps > 0.3) ? speedMps : defaultWalkMps);

  ModeRoute withModes(Set<RouteMode> m) => ModeRoute(modes: m, target: target, nodes: nodes, points: points, tunnelIds: tunnelIds, tunnelLengths: tunnelLengths, distanceM: distanceM, litPct: litPct, aidsPassed: aidsPassed, hazardsNear: hazardsNear, cost: cost);

  /// The same route as an [EvacRoute], so the existing turn-by-turn and progress helpers apply.
  EvacRoute get asEvacRoute => EvacRoute(exit: target.asExit, nodes: nodes, points: points, distanceM: distanceM, tunnelIds: tunnelIds, tunnelLengths: tunnelLengths);
}

class _Edge {
  _Edge({required this.tunnel, required this.lengthM, required this.slope, required this.aids, required this.hazardMult, required this.minHazardM});
  final LayoutTunnel tunnel;
  final double lengthM;
  final double slope; // fraction (0.015 = 1.5 %)
  final List<LayoutAid> aids;
  final double hazardMult;
  final double minHazardM;
  double congestion = 1;
}

/// Four shortest-path modes over the mine layout (CLAUDE.md section 23.4). Pure and synchronous: build it again when
/// hazards, congestion or the layout change.
class RoutePlanner {
  RoutePlanner._(this.layout, this._edges, this._adj, this.closed);

  final MineLayoutData layout;
  final Map<String, _Edge> _edges;
  final Map<String, List<(String, String)>> _adj; // node -> (neighbour, tunnelId)

  /// Tunnels removed by the hard rules (blocked, or within 15 m of a closing hazard).
  final Set<String> closed;

  factory RoutePlanner.build(MineLayoutData layout, {List<RouteHazard> hazards = const [], Map<String, int> peopleInTunnel = const {}, Set<String> extraBlocked = const {}}) {
    final edges = <String, _Edge>{};
    final adj = <String, List<(String, String)>>{for (final j in layout.junctions) j.id: []};
    final closed = <String>{};
    for (final t in layout.tunnels) {
      var minD = double.infinity;
      var mult = 1.0;
      var hard = t.blocked || extraBlocked.contains(t.id);
      for (final h in hazards) {
        final d = _distToPolyline(h.point, t.coords);
        minD = math.min(minD, d);
        if (h.closesTunnels && d <= hardHazardRadiusM) hard = true;
        if (d < softHazardRadiusM) mult *= 1 + h.weight * (1 - d / softHazardRadiusM);
      }
      if (hard) {
        closed.add(t.id);
        continue;
      }
      final aids = [for (final a in layout.aids) if (_distToPolyline(a.point, t.coords) <= aidRadiusM) a];
      final e = _Edge(tunnel: t, lengthM: t.lengthM, slope: t.slopePct / 100, aids: aids, hazardMult: mult, minHazardM: minD);
      final load = peopleInTunnel[t.id] ?? 0;
      final cap = t.capacity <= 0 ? 1 : t.capacity;
      e.congestion = 1 + 0.5 * math.pow(math.max(0, load / cap - 1), 2);
      edges[t.id] = e;
      adj.putIfAbsent(t.from, () => []).add((t.to, t.id));
      adj.putIfAbsent(t.to, () => []).add((t.from, t.id));
    }
    return RoutePlanner._(layout, edges, adj, closed);
  }

  static double _distToPolyline(GeoPoint p, List<GeoPoint> line) {
    var best = double.infinity;
    for (var i = 1; i < line.length; i++) {
      best = math.min(best, distToSegmentM(p, line[i - 1], line[i]));
    }
    return line.length == 1 ? haversineM(p, line.first) : best;
  }

  /// Tobler hiking speed (km/h) × 0.8 underground, in m/s.
  static double toblerMps(double slope) => 6 * math.exp(-3.5 * (slope + 0.05).abs()) * 0.8 / 3.6;

  /// Edge cost for one mode (CLAUDE.md section 23.4 table).
  static double costOf(RouteMode m, {required double lengthM, required double slope, required double widthM, required double? lux, required int aidCount, double hazardMult = 1, double congestion = 1}) {
    switch (m) {
      case RouteMode.leastHindrance:
        final steep = 1 + math.max(0, slope.abs() - 0.08) * 5;
        return lengthM / toblerMps(slope) * hazardMult * congestion * (widthM < 2.0 ? 1.2 : 1.0) * steep;
      case RouteMode.mostLight:
        final l = math.min(lux ?? 0, 200) / 200;
        return lengthM * (1 + 1.5 * (1 - l));
      case RouteMode.mostAid:
        return lengthM * math.max(0.4, 1 - 0.15 * aidCount);
      case RouteMode.direct:
        return lengthM;
    }
  }

  double _cost(RouteMode m, _Edge e) => costOf(m, lengthM: e.lengthM, slope: e.slope, widthM: e.tunnel.widthM, lux: e.tunnel.lightLux, aidCount: e.aids.length, hazardMult: e.hazardMult, congestion: e.congestion);

  /// Every routable place: exits, refuges, aid points, junctions.
  List<RouteTarget> get targets => [
        for (final x in layout.exits) RouteTarget(id: x.id, name: x.name, kind: TargetKind.exit, point: x.point, node: x.node),
        for (final r in layout.refuges) RouteTarget(id: r.id, name: r.name, kind: TargetKind.refuge, point: r.point, node: r.node),
        for (final a in layout.aids) RouteTarget(id: a.id, name: a.name, kind: TargetKind.aid, point: a.point, node: a.node, aidType: a.aidType),
        for (final j in layout.junctions) RouteTarget(id: j.id, name: 'Junction ${j.id}', kind: TargetKind.junction, point: j.point, node: j.id),
      ];

  RouteTarget? target(String id) => targets.where((t) => t.id == id).firstOrNull;

  String? nearestJunction(GeoPoint p) {
    String? best;
    var bestD = double.infinity;
    for (final j in layout.junctions) {
      final d = haversineM(p, j.point);
      if (d < bestD) {
        bestD = d;
        best = j.id;
      }
    }
    return best;
  }

  /// A long-pressed point becomes a junction target (snapped to the nearest junction).
  RouteTarget? targetNear(GeoPoint p) {
    final n = nearestJunction(p);
    return n == null ? null : target(n);
  }

  /// Best route for one mode, or null when the destination cannot be reached safely.
  ModeRoute? route(String start, RouteTarget dest, RouteMode mode) {
    final dist = <String, double>{start: 0};
    final prev = <String, (String, String)>{}; // node -> (previous node, tunnel)
    final done = <String>{};
    final open = <String>{start};
    while (open.isNotEmpty) {
      final u = open.reduce((a, b) => dist[a]! <= dist[b]! ? a : b);
      open.remove(u);
      if (u == dest.node) break;
      if (!done.add(u)) continue;
      for (final (v, id) in _adj[u] ?? const <(String, String)>[]) {
        final nd = dist[u]! + _cost(mode, _edges[id]!);
        if (nd < (dist[v] ?? double.infinity)) {
          dist[v] = nd;
          prev[v] = (u, id);
          open.add(v);
        }
      }
    }
    if (!dist.containsKey(dest.node)) return null;
    final nodes = <String>[dest.node];
    final ids = <String>[];
    while (nodes.first != start) {
      final (p, id) = prev[nodes.first]!;
      ids.insert(0, id);
      nodes.insert(0, p);
    }
    return _describe({mode}, dest, nodes, ids, dist[dest.node]!);
  }

  ModeRoute _describe(Set<RouteMode> modes, RouteTarget dest, List<String> nodes, List<String> ids, double cost) {
    final pts = {for (final j in layout.junctions) j.id: j.point};
    final lens = [for (final id in ids) _edges[id]!.lengthM];
    final total = lens.fold<double>(0, (a, b) => a + b);
    var lit = 0.0;
    final aids = <String, LayoutAid>{};
    var near = 0;
    for (var i = 0; i < ids.length; i++) {
      final e = _edges[ids[i]]!;
      if ((e.tunnel.lightLux ?? 0) >= litLux) lit += lens[i];
      for (final a in e.aids) {
        aids[a.id] = a;
      }
      if (e.minHazardM < softHazardRadiusM) near++;
    }
    return ModeRoute(
      modes: modes,
      target: dest,
      nodes: nodes,
      points: [for (final n in nodes) pts[n] ?? dest.point],
      tunnelIds: ids,
      tunnelLengths: lens,
      distanceM: total,
      litPct: total == 0 ? 1 : lit / total,
      aidsPassed: aids.values.toList(),
      hazardsNear: near,
      cost: cost,
    );
  }

  /// All four modes from [start] to [dest]; identical paths are merged into one route carrying every mode's label.
  /// Ordered by mode (LEAST_HINDRANCE first).
  List<ModeRoute> plan(String start, RouteTarget dest) {
    final byKey = <String, ModeRoute>{};
    for (final m in RouteMode.values) {
      final r = route(start, dest, m);
      if (r == null) continue;
      final hit = byKey[r.key];
      byKey[r.key] = hit == null ? r : hit.withModes({...hit.modes, m});
    }
    return byKey.values.toList()..sort((a, b) => a.primary.index.compareTo(b.primary.index));
  }

  /// People per tunnel from live positions (map-matched tunnelId first, else the nearest tunnel within 15 m).
  static Map<String, int> loadFrom(Iterable<({GeoPoint at, String? tunnelId})> people, MineLayoutData layout) {
    final out = <String, int>{};
    for (final p in people) {
      var id = p.tunnelId;
      if (id == null) {
        var best = 15.0;
        for (final t in layout.tunnels) {
          final d = _distToPolyline(p.at, t.coords);
          if (d <= best) {
            best = d;
            id = t.id;
          }
        }
      }
      if (id != null) out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }
}
