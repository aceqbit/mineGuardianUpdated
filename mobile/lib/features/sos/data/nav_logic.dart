import 'dart:math' as math;

import '../../../core/location/location_service.dart';
import '../../../core/models/mine_layout.dart';
import 'evac_graph.dart';

/// Why the current target exit was chosen. Shown to the worker so the route never feels arbitrary.
enum TargetReason {
  /// The control room sent a route (always wins).
  controlRoom,

  /// The admin's designated emergency exit for this zone.
  designated,

  /// The admin's exit is blocked or unreachable, so the nearest safe exit is used instead.
  designatedUnavailable,

  /// No designated exit: nearest safe exit.
  nearest,

  /// The worker picked a different route themselves.
  workerChoice,
}

class TargetChoice {
  const TargetChoice({required this.route, required this.reason, required this.alternatives});
  final EvacRoute? route;
  final TargetReason reason;

  /// Up to 3 routes, best first; always contains [route] and, when reachable, the designated exit.
  final List<EvacRoute> alternatives;
}

/// Pure target selection. Order: worker's own pick, then admin-designated exit (if reachable), then nearest safe exit.
/// (The control room's route is handled by the caller because it carries its own geometry.)
TargetChoice chooseTarget({
  required EvacGraph graph,
  required GeoPoint? from,
  required String? designatedExitId,
  required String? workerPickedExitId,
  String? fallbackStartNode,
}) {
  final start = from != null ? graph.nearestJunction(from) : fallbackStartNode;
  if (start == null) return const TargetChoice(route: null, reason: TargetReason.nearest, alternatives: []);
  var alts = graph.alternativeRoutes(start);
  final designated = designatedExitId == null ? null : graph.routeToExit(start, designatedExitId);
  if (designated != null && !alts.any((r) => r.exit.id == designated.exit.id)) {
    alts = [...alts.take(2), designated]..sort((a, b) => a.distanceM.compareTo(b.distanceM));
  }
  if (alts.isEmpty) return TargetChoice(route: null, reason: designatedExitId == null ? TargetReason.nearest : TargetReason.designatedUnavailable, alternatives: const []);

  final picked = workerPickedExitId == null ? null : alts.where((r) => r.exit.id == workerPickedExitId).firstOrNull;
  if (picked != null) {
    final reason = picked.exit.id == designatedExitId ? TargetReason.designated : TargetReason.workerChoice;
    return TargetChoice(route: picked, reason: reason, alternatives: alts);
  }
  if (designated != null) return TargetChoice(route: alts.firstWhere((r) => r.exit.id == designated.exit.id), reason: TargetReason.designated, alternatives: alts);
  return TargetChoice(route: alts.first, reason: designatedExitId == null ? TargetReason.nearest : TargetReason.designatedUnavailable, alternatives: alts);
}

// ---------------------------------------------------------------------------------------------------------------- turns

enum Turn { start, straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, arrive }

class NavStep {
  const NavStep({required this.turn, required this.text, required this.distanceM, required this.startPoint, required this.endPoint});
  final Turn turn;

  /// e.g. "Turn left, then walk 60 m".
  final String text;

  /// Length of the walk that follows the manoeuvre.
  final double distanceM;

  /// Index into `route.points` where this step begins and ends.
  final int startPoint;
  final int endPoint;
}

double bearingDeg(GeoPoint a, GeoPoint b) {
  final cosLat = math.cos(a.lat * math.pi / 180);
  final dx = (b.lng - a.lng) * cosLat;
  final dy = b.lat - a.lat;
  return (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
}

/// Signed change of direction in degrees: negative = left, positive = right, range -180..180.
double turnAngle(double fromBearing, double toBearing) {
  var d = (toBearing - fromBearing + 540) % 360 - 180;
  if (d == -180) d = 180;
  return d;
}

Turn classifyTurn(double angle) {
  final a = angle.abs();
  if (a < 25) return Turn.straight;
  final left = angle < 0;
  if (a < 60) return left ? Turn.slightLeft : Turn.slightRight;
  if (a < 120) return left ? Turn.left : Turn.right;
  return left ? Turn.sharpLeft : Turn.sharpRight;
}

String _turnWord(Turn t) => switch (t) {
      Turn.start => 'Start walking',
      Turn.straight => 'Continue straight',
      Turn.slightLeft => 'Bear left',
      Turn.left => 'Turn left',
      Turn.sharpLeft => 'Turn sharp left',
      Turn.slightRight => 'Bear right',
      Turn.right => 'Turn right',
      Turn.sharpRight => 'Turn sharp right',
      Turn.arrive => 'Arrive',
    };

/// Turn-by-turn steps from the junction sequence of [route]. Straight stretches are merged into one step.
List<NavStep> buildSteps(EvacRoute route) {
  final pts = route.points;
  if (pts.length < 2) return [NavStep(turn: Turn.arrive, text: 'You are at ${route.exit.name}', distanceM: 0, startPoint: 0, endPoint: 0)];
  final legLen = [for (var i = 1; i < pts.length; i++) haversineM(pts[i - 1], pts[i])];
  final bearings = [for (var i = 1; i < pts.length; i++) bearingDeg(pts[i - 1], pts[i])];
  final steps = <NavStep>[];
  var begin = 0;
  var turn = Turn.start;
  var dist = legLen[0];
  void close(int endPoint) {
    steps.add(NavStep(turn: turn, text: '${_turnWord(turn)}, then walk ${_dist(dist)}', distanceM: dist, startPoint: begin, endPoint: endPoint));
  }

  for (var i = 1; i < legLen.length; i++) {
    final t = classifyTurn(turnAngle(bearings[i - 1], bearings[i]));
    if (t == Turn.straight) {
      dist += legLen[i];
    } else {
      close(i);
      begin = i;
      turn = t;
      dist = legLen[i];
    }
  }
  close(pts.length - 1);
  steps.add(NavStep(turn: Turn.arrive, text: 'Arrive at ${route.exit.name}', distanceM: 0, startPoint: pts.length - 1, endPoint: pts.length - 1));
  return steps;
}

String _dist(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${(m / 5).round() * 5 == 0 ? m.round() : (m / 5).round() * 5} m';

// -------------------------------------------------------------------------------------------------------------- progress

class RouteProgress {
  const RouteProgress({required this.segment, required this.fraction, required this.remainingM, required this.travelled, required this.remaining, required this.offRouteM});

  /// Index of the segment (between points[segment] and points[segment+1]) the worker is nearest to.
  final int segment;
  final double fraction;
  final double remainingM;
  final List<GeoPoint> travelled;
  final List<GeoPoint> remaining;
  final double offRouteM;
}

RouteProgress routeProgress(EvacRoute route, GeoPoint at) {
  final pts = route.points;
  if (pts.length < 2) return RouteProgress(segment: 0, fraction: 0, remainingM: 0, travelled: pts, remaining: pts, offRouteM: 0);
  var best = double.infinity;
  var bestSeg = 0;
  var bestT = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final d = distToSegmentM(at, pts[i - 1], pts[i]);
    if (d < best) {
      best = d;
      bestSeg = i - 1;
      bestT = _fraction(at, pts[i - 1], pts[i]);
    }
  }
  final a = pts[bestSeg], b = pts[bestSeg + 1];
  final snapped = GeoPoint(a.lat + (b.lat - a.lat) * bestT, a.lng + (b.lng - a.lng) * bestT);
  var rem = haversineM(snapped, b);
  for (var i = bestSeg + 2; i < pts.length; i++) {
    rem += haversineM(pts[i - 1], pts[i]);
  }
  return RouteProgress(
    segment: bestSeg,
    fraction: bestT,
    remainingM: rem,
    travelled: [...pts.take(bestSeg + 1), snapped],
    remaining: [snapped, ...pts.skip(bestSeg + 1)],
    offRouteM: best,
  );
}

double _fraction(GeoPoint p, GeoPoint a, GeoPoint b) {
  final k = 111320.0;
  final cosLat = math.cos(p.lat * math.pi / 180);
  double x(GeoPoint q) => (q.lng - p.lng) * k * cosLat;
  double y(GeoPoint q) => (q.lat - p.lat) * k;
  final ax = x(a), ay = y(a), dx = x(b) - ax, dy = y(b) - ay;
  final len2 = dx * dx + dy * dy;
  return len2 == 0 ? 0 : (((-ax) * dx + (-ay) * dy) / len2).clamp(0.0, 1.0);
}

/// The step the worker is currently on and the metres left before the next manoeuvre.
({NavStep step, NavStep? next, double metresToNext}) currentStep(List<NavStep> steps, EvacRoute route, RouteProgress p) {
  final pts = route.points;
  var idx = 0;
  final atEnd = p.remainingM < 5; // within 5 m of the exit point counts as the arrival step
  if (atEnd) idx = steps.length - 1;
  for (var i = 0; !atEnd && i < steps.length; i++) {
    if (steps[i].turn == Turn.arrive) {
      idx = i;
      break;
    }
    if (p.segment >= steps[i].startPoint && p.segment < steps[i].endPoint) {
      idx = i;
      break;
    }
  }
  final step = steps[idx];
  final next = idx + 1 < steps.length ? steps[idx + 1] : null;
  // metres from the worker to the end of this step along the route
  var left = haversineM(p.remaining.first, pts[math.min(p.segment + 1, pts.length - 1)]);
  for (var i = p.segment + 2; i <= step.endPoint && i < pts.length; i++) {
    left += haversineM(pts[i - 1], pts[i]);
  }
  return (step: step, next: next, metresToNext: step.turn == Turn.arrive ? 0 : left);
}

// ------------------------------------------------------------------------------------------------------------ simulation

/// Walks a position along [route] for demos and tests when there is no real GPS.
/// [speedMps] is the simulated speed; fixes are produced every [step].
Stream<LocationFix> simulateWalk(EvacRoute route, {double speedMps = 4.0, Duration step = const Duration(milliseconds: 500), DateTime Function()? clock}) async* {
  final now = clock ?? DateTime.now;
  final pts = route.points;
  if (pts.length < 2) return;
  final perTick = speedMps * step.inMilliseconds / 1000;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final len = haversineM(a, b);
    final n = math.max(1, (len / perTick).ceil());
    final heading = bearingDeg(a, b);
    for (var k = 1; k <= n; k++) {
      final f = k / n;
      yield LocationFix(lat: a.lat + (b.lat - a.lat) * f, lng: a.lng + (b.lng - a.lng) * f, accuracyM: 5, ts: now().toUtc(), headingDeg: heading, speedMps: speedMps);
      await Future<void>.delayed(step);
    }
  }
}
