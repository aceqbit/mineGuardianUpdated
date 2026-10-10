import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/core/models/mine_layout.dart';
import 'package:mine_guardian/features/sos/data/evac_graph.dart';
import 'package:mine_guardian/features/sos/data/nav_logic.dart';

import 'fixtures/layout_fixture.dart';

void main() {
  final layout = MineLayoutData.fromJson(jsonDecode(layoutFixtureJson) as Map<String, dynamic>);
  final graph = EvacGraph.build(layout);
  GeoPoint j(String id) => layout.junctions.firstWhere((x) => x.id == id).point;
  final startPoint = j('J5');
  final nearest = graph.routeFrom(startPoint)!;
  final otherExit = layout.exits.firstWhere((e) => e.id != nearest.exit.id);

  group('target selection', () {
    test('without a designated exit the nearest safe exit is used', () {
      final c = chooseTarget(graph: graph, from: startPoint, designatedExitId: null, workerPickedExitId: null);
      expect(c.route!.exit.id, nearest.exit.id);
      expect(c.reason, TargetReason.nearest);
      expect(c.alternatives, isNotEmpty);
    });

    test('the admin-designated exit wins over a nearer one, and is always offered', () {
      final c = chooseTarget(graph: graph, from: startPoint, designatedExitId: otherExit.id, workerPickedExitId: null);
      expect(c.route!.exit.id, otherExit.id);
      expect(c.reason, TargetReason.designated);
      expect(c.alternatives.map((r) => r.exit.id), contains(otherExit.id));
    });

    test('a blocked designated exit falls back to the nearest safe exit with a clear reason', () {
      final dest = graph.routeToExit(graph.nearestJunction(startPoint)!, otherExit.id)!;
      // Block every tunnel touching the designated exit's junction.
      final blocked = layout.tunnels.where((t) => t.from == otherExit.node || t.to == otherExit.node).map((t) => t.id).toSet();
      expect(dest.distanceM, greaterThan(0));
      final g2 = EvacGraph.build(layout, extraBlocked: blocked);
      final c = chooseTarget(graph: g2, from: startPoint, designatedExitId: otherExit.id, workerPickedExitId: null);
      expect(c.route, isNotNull);
      expect(c.route!.exit.id, isNot(otherExit.id));
      expect(c.reason, TargetReason.designatedUnavailable);
    });

    test('the worker picking a route overrides the designated exit', () {
      final c = chooseTarget(graph: graph, from: startPoint, designatedExitId: otherExit.id, workerPickedExitId: nearest.exit.id);
      expect(c.route!.exit.id, nearest.exit.id);
      expect(c.reason, TargetReason.workerChoice);
    });

    test('with nothing reachable the choice is empty, not a crash', () {
      final g2 = EvacGraph.build(layout, extraBlocked: layout.tunnels.map((t) => t.id).toSet());
      final c = chooseTarget(graph: g2, from: startPoint, designatedExitId: otherExit.id, workerPickedExitId: null);
      expect(c.route, isNull);
    });
  });

  group('turn by turn', () {
    test('turn angles classify left, right and straight', () {
      expect(classifyTurn(turnAngle(0, 90)), Turn.right);
      expect(classifyTurn(turnAngle(0, 270)), Turn.left);
      expect(classifyTurn(turnAngle(0, 10)), Turn.straight);
      expect(classifyTurn(turnAngle(350, 10)), Turn.straight);
      expect(classifyTurn(turnAngle(0, 180)), Turn.sharpRight);
      expect(classifyTurn(turnAngle(0, 40)), Turn.slightRight);
    });

    test('steps cover the whole route and end with arrival', () {
      final steps = buildSteps(nearest);
      expect(steps.first.turn, Turn.start);
      expect(steps.last.turn, Turn.arrive);
      expect(steps.last.text, contains(nearest.exit.name));
      final walked = steps.fold<double>(0, (a, s) => a + s.distanceM);
      expect(walked, closeTo(nearest.distanceM, nearest.distanceM * 0.01 + 1));
    });
  });

  group('progress', () {
    test('at the start nothing is travelled; remaining equals the route', () {
      final p = routeProgress(nearest, nearest.points.first);
      expect(p.remainingM, closeTo(nearest.distanceM, 2));
      expect(p.offRouteM, closeTo(0, 0.5));
    });

    test('halfway along, remaining shrinks and the travelled part grows', () {
      final a = nearest.points.first, b = nearest.points[1];
      final mid = GeoPoint((a.lat + b.lat) / 2, (a.lng + b.lng) / 2);
      final p = routeProgress(nearest, mid);
      expect(p.remainingM, lessThan(nearest.distanceM));
      expect(p.remainingM, greaterThan(nearest.distanceM - haversineM(a, b) - 1));
      expect(p.travelled.length, greaterThanOrEqualTo(2));
      expect(p.remaining.first.lat, closeTo(mid.lat, 1e-6));
    });

    test('current step reports the distance to the next manoeuvre', () {
      final steps = buildSteps(nearest);
      final p = routeProgress(nearest, nearest.points.first);
      final cs = currentStep(steps, nearest, p);
      expect(cs.step.turn, Turn.start);
      expect(cs.metresToNext, greaterThan(0));
      final end = routeProgress(nearest, nearest.points.last);
      expect(currentStep(steps, nearest, end).step.turn, Turn.arrive);
    });
  });

  test('the walk simulator reaches the exit and reports heading', () async {
    final fixes = await simulateWalk(nearest, speedMps: 400, step: const Duration(milliseconds: 1)).toList();
    expect(fixes, isNotEmpty);
    expect(fixes.first.headingDeg, isNotNull);
    final last = fixes.last;
    expect(haversineM(GeoPoint(last.lat, last.lng), nearest.exit.point), lessThan(1));
  });
}
