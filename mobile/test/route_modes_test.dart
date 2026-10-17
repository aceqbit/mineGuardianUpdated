import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/contracts/enums.dart';
import 'package:mine_guardian/core/models/mine_layout.dart';
import 'package:mine_guardian/core/sensors/local_frame.dart';
import 'package:mine_guardian/features/live_map/data/route_modes.dart';
import 'package:mine_guardian/features/sos/data/nav_logic.dart';

final frame = LocalFrame(23.746, 86.415);
GeoPoint at(double x, double y) {
  final p = frame.toLatLng(x, y);
  return GeoPoint(p.lat, p.lng);
}

LayoutTunnel tunnel(String from, String to, Map<String, GeoPoint> n, {double lux = 150, double width = 3.5, double slope = 0, bool blocked = false}) => LayoutTunnel(
      id: 'T-$from-$to', from: from, to: to, widthM: width, capacity: 10, slopePct: slope, airway: 'intake', blocked: blocked, coords: [n[from]!, n[to]!], lightLux: lux);

/// A —100 m— B —100 m (UNLIT)— C is the direct way; A — D — C is a lit 233 m detour with two aid points at D.
MineLayoutData testMine() {
  final n = {'A': at(0, 0), 'B': at(100, 0), 'C': at(200, 0), 'D': at(100, 60)};
  return MineLayoutData(
    version: 2,
    anchor: const GeoPoint(23.746, 86.415),
    zones: const [],
    tunnels: [tunnel('A', 'B', n), tunnel('B', 'C', n, lux: 0), tunnel('A', 'D', n), tunnel('D', 'C', n)],
    junctions: [for (final e in n.entries) LayoutJunction(e.key, e.value)],
    exits: [LayoutExit(id: 'X-C', name: 'Exit C', exitType: 'shaft', point: n['C']!, node: 'C')],
    refuges: const [],
    aids: [
      LayoutAid(id: 'FA-D', aidType: 'FIRST_AID', name: 'First aid D', point: n['D']!, node: 'D'),
      LayoutAid(id: 'PH-D', aidType: 'PHONE', name: 'Phone D', point: n['D']!, node: 'D'),
    ],
  );
}

void main() {
  final mine = testMine();
  final exitC = RoutePlanner.build(mine).target('X-C')!;

  test('DIRECT is the minimum-length path; LEAST_HINDRANCE agrees with no hazards', () {
    final p = RoutePlanner.build(mine);
    expect(p.route('A', exitC, RouteMode.direct)!.nodes, ['A', 'B', 'C']);
    expect(p.route('A', exitC, RouteMode.direct)!.distanceM, closeTo(200, 1));
    expect(p.route('A', exitC, RouteMode.leastHindrance)!.nodes, ['A', 'B', 'C']);
  });

  test('MOST_LIGHT avoids the unlit span and reports the lit share', () {
    final p = RoutePlanner.build(mine);
    final light = p.route('A', exitC, RouteMode.mostLight)!;
    expect(light.nodes, ['A', 'D', 'C']);
    expect(light.litPct, 1.0);
    expect(p.route('A', exitC, RouteMode.direct)!.litPct, closeTo(0.5, 0.01));
  });

  test('MOST_AID passes at least one more aid point than DIRECT', () {
    final p = RoutePlanner.build(mine);
    final aid = p.route('A', exitC, RouteMode.mostAid)!;
    final direct = p.route('A', exitC, RouteMode.direct)!;
    expect(aid.nodes, ['A', 'D', 'C']);
    expect(aid.aidsPassed.length, greaterThan(direct.aidsPassed.length));
  });

  test('identical paths are drawn once, carrying every mode that chose them', () {
    final routes = RoutePlanner.build(mine).plan('A', exitC);
    expect(routes.length, 2);
    final direct = routes.firstWhere((r) => r.nodes.join() == 'ABC');
    final detour = routes.firstWhere((r) => r.nodes.join() == 'ADC');
    expect(direct.modes, {RouteMode.leastHindrance, RouteMode.direct});
    expect(detour.modes, {RouteMode.mostLight, RouteMode.mostAid});
    expect(routes.first.primary, RouteMode.leastHindrance);
  });

  test('a nearby MEDIUM hazard pushes LEAST_HINDRANCE onto the detour but not DIRECT', () {
    final p = RoutePlanner.build(mine, hazards: [RouteHazard(point: at(100, -5), category: 'EQUIPMENT_FAILURE', severity: 'MEDIUM')]);
    expect(p.closed, isEmpty);
    expect(p.route('A', exitC, RouteMode.leastHindrance)!.nodes, ['A', 'D', 'C']);
    expect(p.route('A', exitC, RouteMode.direct)!.nodes, ['A', 'B', 'C']);
    expect(p.route('A', exitC, RouteMode.direct)!.hazardsNear, 2);
  });

  test('every mode avoids a tunnel within 15 m of a CRITICAL (or unclassified closing) hazard', () {
    for (final h in [RouteHazard(point: at(150, 4), category: 'OTHER', severity: 'CRITICAL'), RouteHazard(point: at(150, 10), category: 'FIRE_SMOKE')]) {
      final p = RoutePlanner.build(mine, hazards: [h]);
      expect(p.closed, {'T-B-C'});
      final routes = p.plan('A', exitC);
      expect(routes.length, 1);
      expect(routes.single.nodes, ['A', 'D', 'C']);
      expect(routes.single.modes, RouteMode.values.toSet());
    }
  });

  test('a blocked tunnel and a fully closed mine give no route rather than a wrong one', () {
    final blocked = MineLayoutData(version: 2, anchor: mine.anchor, zones: const [], junctions: mine.junctions, exits: mine.exits, refuges: const [], aids: mine.aids, tunnels: [
      for (final t in mine.tunnels) LayoutTunnel(id: t.id, from: t.from, to: t.to, widthM: t.widthM, capacity: t.capacity, slopePct: t.slopePct, airway: t.airway, blocked: true, coords: t.coords, lightLux: t.lightLux),
    ]);
    expect(RoutePlanner.build(blocked).plan('A', exitC), isEmpty);
  });

  test('congestion over capacity makes LEAST_HINDRANCE prefer the empty way', () {
    final p = RoutePlanner.build(mine, peopleInTunnel: {'T-A-B': 40});
    expect(p.route('A', exitC, RouteMode.leastHindrance)!.nodes, ['A', 'D', 'C']);
    expect(p.route('A', exitC, RouteMode.direct)!.nodes, ['A', 'B', 'C']);
  });

  test('cost table: narrow tunnels cost 20% more time, Tobler peaks downhill at -5%', () {
    final wide = RoutePlanner.costOf(RouteMode.leastHindrance, lengthM: 100, slope: 0, widthM: 3, lux: 150, aidCount: 0);
    final narrow = RoutePlanner.costOf(RouteMode.leastHindrance, lengthM: 100, slope: 0, widthM: 1.8, lux: 150, aidCount: 0);
    expect(narrow / wide, closeTo(1.2, 1e-9));
    expect(RoutePlanner.toblerMps(-0.05), greaterThan(RoutePlanner.toblerMps(0)));
    expect(RoutePlanner.costOf(RouteMode.mostAid, lengthM: 100, slope: 0, widthM: 3, lux: 0, aidCount: 10), 40);
  });

  test('targets include exits, aid points and junctions; a long-press snaps to the nearest junction', () {
    final p = RoutePlanner.build(mine);
    expect(p.targets.map((t) => t.kind).toSet(), {TargetKind.exit, TargetKind.aid, TargetKind.junction});
    expect(p.targetNear(at(95, 55))!.node, 'D');
  });

  test('a mode route plugs into the existing turn-by-turn helpers', () {
    final r = RoutePlanner.build(mine).route('A', exitC, RouteMode.mostLight)!;
    final steps = buildSteps(r.asEvacRoute);
    expect(steps.last.turn, Turn.arrive);
    expect(routeProgress(r.asEvacRoute, at(100, 58)).offRouteM, lessThan(5));
    expect(r.etaSec(), closeTo(r.distanceM / defaultWalkMps, 1e-9));
  });

  test('people per tunnel from live positions', () {
    final load = RoutePlanner.loadFrom([(at: at(50, 2), tunnelId: null), (at: at(500, 500), tunnelId: null), (at: at(0, 0), tunnelId: 'T-D-C')], mine);
    expect(load, {'T-A-B': 1, 'T-D-C': 1});
  });

  test('the seeded layout parses lightLux and aid points', () {
    final j = {
      'version': 2,
      'anchor': {'lat': 23.746, 'lng': 86.415},
      'geojson': {
        'type': 'FeatureCollection',
        'features': [
          {'type': 'Feature', 'properties': {'kind': 'junction', 'id': 'J0'}, 'geometry': {'type': 'Point', 'coordinates': [86.41, 23.74]}},
          {'type': 'Feature', 'properties': {'kind': 'tunnel', 'id': 'T-J0-J1', 'fromNode': 'J0', 'toNode': 'J1', 'widthM': 3.5, 'capacity': 20, 'slopePct': 1.5, 'airway': 'intake', 'status': 'open', 'lightLux': 0}, 'geometry': {'type': 'LineString', 'coordinates': [[86.41, 23.74], [86.411, 23.74]]}},
          {'type': 'Feature', 'properties': {'kind': 'aid', 'id': 'AID-PH-J0', 'aidType': 'PHONE', 'name': 'Phone', 'node': 'J0'}, 'geometry': {'type': 'Point', 'coordinates': [86.41, 23.74]}},
        ],
      },
    };
    final l = MineLayoutData.fromJson(j);
    expect(l.tunnels.single.lightLux, 0);
    expect(l.aids.single.aidType, 'PHONE');
  });
}
