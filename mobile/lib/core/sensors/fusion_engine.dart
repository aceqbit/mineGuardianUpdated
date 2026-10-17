import 'dart:math' as math;

import '../../contracts/enums.dart';
import 'local_frame.dart';
import 'map_matcher.dart';
import 'position_kalman.dart';

/// One fused position, ready for `gps:update`.
class FusedFix {
  const FusedFix({required this.lat, required this.lng, required this.accuracyM, required this.ts, required this.source, this.headingDeg, this.speedMps, this.tunnelId, this.x = 0, this.y = 0});
  final double lat;
  final double lng;
  final double accuracyM;
  final DateTime ts;
  final PositionSource source;
  final double? headingDeg;
  final double? speedMps;
  final String? tunnelId;

  /// Local metres (for movement checks).
  final double x;
  final double y;

  Map<String, dynamic> toGpsUpdate({String? sosId}) => {
        'lat': lat,
        'lng': lng,
        'accuracyM': double.parse(accuracyM.toStringAsFixed(1)),
        'ts': ts.toUtc().toIso8601String(),
        'source': source.wire,
        if (headingDeg != null) 'headingDeg': double.parse(headingDeg!.toStringAsFixed(1)) % 360,
        if (speedMps != null) 'speedMps': double.parse(speedMps!.clamp(0, 20).toStringAsFixed(2)),
        'tunnelId': ?tunnelId,
        'sosId': ?sosId,
      };
}

/// GPS + pedestrian dead reckoning (CLAUDE.md section 23.3). Pure: feed it samples, read [current].
/// GPS ≤ 30 m and fresh (≤ 10 s) → GPS (FUSED when steps were taken since); otherwise PDR. Fixes worse than
/// [gateM] are ignored once the filter is running (underground multipath), except to initialise it.
class FusionEngine {
  FusionEngine({required this.frame, this.matcher, this.goodGpsM = 30, this.gateM = 50, this.gpsFreshFor = const Duration(seconds: 10)});

  final LocalFrame frame;
  MapMatcher? matcher;
  final double goodGpsM;
  final double gateM;
  final Duration gpsFreshFor;

  final PositionKalman _kf = PositionKalman();
  DateTime? _lastGoodGps;
  DateTime? _lastTime;
  double? _heading;
  double? _gpsSpeed;
  int _stepsSinceGps = 0;
  final List<(DateTime, double)> _recentSteps = [];

  bool get hasFix => _kf.initialized;

  void setHeading(double? deg) => _heading = deg;

  void _advance(DateTime t) {
    final last = _lastTime;
    if (last != null && t.isAfter(last)) _kf.elapse(t.difference(last).inMilliseconds / 1000);
    if (last == null || t.isAfter(last)) _lastTime = t;
  }

  void addGps({required double lat, required double lng, required double accuracyM, required DateTime ts, double? speedMps, double? headingDeg}) {
    _advance(ts);
    final p = frame.toXY(lat, lng);
    if (_kf.initialized && accuracyM > gateM) return;
    _kf.update(p.x, p.y, accuracyM);
    if (accuracyM <= goodGpsM) {
      _lastGoodGps = ts;
      _stepsSinceGps = 0;
      _gpsSpeed = speedMps;
      if (_heading == null && headingDeg != null) _heading = headingDeg;
    }
  }

  void addStep(double lengthM, DateTime t) {
    _advance(t);
    final h = _heading;
    if (h == null) return; // no heading yet: a step without direction is not a position
    _kf.step(lengthM, h);
    _stepsSinceGps += 1;
    _recentSteps.add((t, lengthM));
    _recentSteps.removeWhere((s) => t.difference(s.$1) > const Duration(seconds: 4));
  }

  PositionSource sourceAt(DateTime now) {
    final g = _lastGoodGps;
    if (g != null && now.difference(g) <= gpsFreshFor) return _stepsSinceGps > 0 ? PositionSource.fused : PositionSource.gps;
    return PositionSource.pdr;
  }

  double? speedAt(DateTime now) {
    _recentSteps.removeWhere((s) => now.difference(s.$1) > const Duration(seconds: 4));
    if (_recentSteps.length >= 2) {
      final span = now.difference(_recentSteps.first.$1).inMilliseconds / 1000;
      final dist = _recentSteps.fold<double>(0, (a, s) => a + s.$2);
      if (span > 0.5) return dist / span;
    }
    if (sourceAt(now) == PositionSource.gps) return _gpsSpeed;
    return _recentSteps.isEmpty ? 0 : null;
  }

  FusedFix? current(DateTime now) {
    if (!_kf.initialized) return null;
    _advance(now);
    var x = _kf.x, y = _kf.y;
    String? tunnelId;
    final m = matcher?.snap(x, y);
    if (m != null) {
      x = m.x;
      y = m.y;
      tunnelId = m.tunnelId;
    }
    final ll = frame.toLatLng(x, y);
    return FusedFix(lat: ll.lat, lng: ll.lng, accuracyM: math.max(1, _kf.sigmaM), ts: now, source: sourceAt(now), headingDeg: _heading, speedMps: speedAt(now), tunnelId: tunnelId, x: x, y: y);
  }
}

/// When to send `gps:update`: every 2 s while moving (> 1 m since the last send), every 10 s while still.
class SendPolicy {
  SendPolicy({this.movingEvery = const Duration(seconds: 2), this.stillEvery = const Duration(seconds: 10), this.moveM = 1});
  final Duration movingEvery;
  final Duration stillEvery;
  final double moveM;
  DateTime? _lastAt;
  double? _lx, _ly;

  bool shouldSend(FusedFix f) {
    final last = _lastAt;
    if (last == null) return true;
    final age = f.ts.difference(last);
    final moved = _lx == null ? true : math.sqrt(math.pow(f.x - _lx!, 2) + math.pow(f.y - _ly!, 2)) > moveM;
    return moved ? age >= movingEvery : age >= stillEvery;
  }

  void sent(FusedFix f) {
    _lastAt = f.ts;
    _lx = f.x;
    _ly = f.y;
  }
}
