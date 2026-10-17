import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/contracts/enums.dart';
import 'package:mine_guardian/core/location/tracking_controller.dart';
import 'package:mine_guardian/core/models/session_user.dart';
import 'package:mine_guardian/core/sensors/fusion_engine.dart';
import 'package:mine_guardian/core/sensors/heading_filter.dart';
import 'package:mine_guardian/core/sensors/local_frame.dart';
import 'package:mine_guardian/core/sensors/map_matcher.dart';
import 'package:mine_guardian/core/sensors/position_kalman.dart';
import 'package:mine_guardian/core/sensors/step_detector.dart';

const g = 9.80665;
final t0 = DateTime.utc(2026, 10, 17, 4, 0);

/// Recorded-style walking trace: 50 Hz, ~1.8 steps/s, vertical bounce ±3.5 m/s² on top of gravity, plus sensor noise.
List<(double, double, double, DateTime)> walkingTrace({required int seconds, double hz = 50, double stepsPerSec = 1.8, double amp = 3.5}) {
  final rnd = math.Random(7);
  final out = <(double, double, double, DateTime)>[];
  for (var i = 0; i < seconds * hz; i++) {
    final t = i / hz;
    final bounce = amp * math.sin(2 * math.pi * stepsPerSec * t);
    out.add((0.3 * (rnd.nextDouble() - 0.5), 0.3 * (rnd.nextDouble() - 0.5), g + bounce + 0.4 * (rnd.nextDouble() - 0.5), t0.add(Duration(microseconds: (t * 1e6).round()))));
  }
  return out;
}

void main() {
  group('StepDetector', () {
    test('counts ~1.8 steps/s while walking (±1 over 10 s)', () {
      final d = StepDetector();
      var n = 0;
      for (final s in walkingTrace(seconds: 10)) {
        if (d.add(s.$1, s.$2, s.$3, s.$4) != null) n++;
      }
      expect(n, inInclusiveRange(17, 19));
    });

    test('counts nothing while standing still or swaying gently', () {
      final d = StepDetector();
      var n = 0;
      for (final s in walkingTrace(seconds: 10, amp: 0.8)) {
        if (d.add(s.$1, s.$2, s.$3, s.$4) != null) n++;
      }
      expect(n, 0);
    });

    test('never counts two steps closer than 300 ms (fast jitter)', () {
      final d = StepDetector();
      var n = 0;
      for (final s in walkingTrace(seconds: 5, stepsPerSec: 6)) {
        if (d.add(s.$1, s.$2, s.$3, s.$4) != null) n++;
      }
      expect(n, lessThanOrEqualTo(17)); // 5 s / 0.3 s
    });

    test('default step length 0.7 m; Weinberg estimate when calibrated', () {
      final d = StepDetector();
      double? len;
      for (final s in walkingTrace(seconds: 3)) {
        len ??= d.add(s.$1, s.$2, s.$3, s.$4);
      }
      expect(len, 0.7);
      final w = StepDetector(weinbergK: 0.45);
      final lens = <double>[];
      for (final s in walkingTrace(seconds: 3)) {
        final l = w.add(s.$1, s.$2, s.$3, s.$4);
        if (l != null) lens.add(l);
      }
      expect(lens.skip(1).every((l) => l > 0.5 && l < 1.0), isTrue, reason: '$lens');
    });
  });

  group('HeadingFilter', () {
    test('flat phone pointing north / east from gravity + field', () {
      // Field points north and down (northern hemisphere). Phone flat, screen up: gravity reading +z.
      expect(HeadingFilter.tiltCompensated(0, 0, g, 0, 30, -40)!, closeTo(0, 0.5));
      // Rotated so the top edge faces east: north is now along -x.
      expect(HeadingFilter.tiltCompensated(0, 0, g, -30, 0, -40)!, closeTo(90, 0.5));
    });

    test('complementary filter follows the gyro and is pulled to the magnetometer, across 0/360', () {
      final f = HeadingFilter();
      f.addMag(350);
      // turn clockwise 20° in 1 s: gz = -20°/s
      for (var i = 0; i <= 50; i++) {
        f.addGyro(-20 * math.pi / 180, t0.add(Duration(milliseconds: 20 * i)));
      }
      expect(angleDiffDeg(f.headingDeg!, 10).abs(), lessThan(1));
      for (var i = 0; i < 400; i++) {
        f.addMag(20);
      }
      expect(angleDiffDeg(f.headingDeg!, 20).abs(), lessThan(0.5));
    });
  });

  group('PositionKalman', () {
    test('accurate GPS dominates, inaccurate GPS barely moves it', () {
      final k = PositionKalman()..update(0, 0, 3);
      k.update(10, 0, 3);
      expect(k.x, closeTo(5, 0.5));
      final before = k.x;
      k.update(200, 0, 200);
      expect((k.x - before).abs(), lessThan(1));
    });

    test('steps move the estimate and grow the uncertainty', () {
      final k = PositionKalman()..update(0, 0, 4);
      final s0 = k.sigmaM;
      for (var i = 0; i < 10; i++) {
        k.step(0.7, 90);
      }
      expect(k.x, closeTo(7, 1e-9));
      expect(k.y, closeTo(0, 1e-9));
      expect(k.sigmaM, greaterThan(s0));
    });
  });

  group('MapMatcher', () {
    final m = MapMatcher.segments([('T-J0-J1', 0, 0, 60, 0), ('T-J1-N1', 60, 0, 60, 120)]);
    test('snaps within 15 m onto the nearest tunnel', () {
      final r = m.snap(30, 9)!;
      expect(r.tunnelId, 'T-J0-J1');
      expect(r.y, 0);
      expect(r.x, closeTo(30, 1e-9));
      expect(m.snap(55, 40)!.tunnelId, 'T-J1-N1');
    });
    test('leaves positions farther than 15 m alone', () {
      expect(m.snap(30, 20), isNull);
    });
  });

  group('FusionEngine', () {
    final frame = LocalFrame(23.746, 86.415);
    ({double lat, double lng}) ll(double x, double y) => frame.toLatLng(x, y);

    test('GPS only -> GPS; steps since the fix -> FUSED; GPS gone 10 s -> PDR', () {
      final e = FusionEngine(frame: frame);
      final p = ll(0, 0);
      e.addGps(lat: p.lat, lng: p.lng, accuracyM: 5, ts: t0);
      expect(e.current(t0.add(const Duration(seconds: 1)))!.source, PositionSource.gps);
      e.setHeading(0);
      e.addStep(0.7, t0.add(const Duration(seconds: 2)));
      expect(e.current(t0.add(const Duration(seconds: 2)))!.source, PositionSource.fused);
      expect(e.current(t0.add(const Duration(seconds: 12)))!.source, PositionSource.pdr);
    });

    test('underground: dead reckoning carries the position north when GPS drops out', () {
      final e = FusionEngine(frame: frame);
      final p = ll(0, 0);
      e.addGps(lat: p.lat, lng: p.lng, accuracyM: 4, ts: t0);
      e.setHeading(0);
      for (var i = 1; i <= 20; i++) {
        e.addStep(0.7, t0.add(Duration(milliseconds: 550 * i)));
      }
      // a wild multipath fix 300 m away is gated out
      final bad = ll(300, 0);
      e.addGps(lat: bad.lat, lng: bad.lng, accuracyM: 80, ts: t0.add(const Duration(seconds: 11)));
      final f = e.current(t0.add(const Duration(seconds: 12)))!;
      expect(f.source, PositionSource.pdr);
      expect(f.y, closeTo(14, 0.5));
      expect(f.x.abs(), lessThan(0.5));
      expect(f.speedMps, isNotNull);
    });

    test('map-matched output carries the tunnel id', () {
      final e = FusionEngine(frame: frame, matcher: MapMatcher.segments([('T-J0-J1', -100, 0, 100, 0)]));
      final p = ll(10, 6);
      e.addGps(lat: p.lat, lng: p.lng, accuracyM: 5, ts: t0);
      final f = e.current(t0)!;
      expect(f.tunnelId, 'T-J0-J1');
      expect(f.y, closeTo(0, 1e-6));
      final wire = f.toGpsUpdate();
      expect(wire['source'], 'GPS');
      expect(wire['tunnelId'], 'T-J0-J1');
      expect(wire.containsKey('sosId'), isFalse);
    });
  });

  group('SendPolicy', () {
    FusedFix at(int sec, double x) => FusedFix(lat: 0, lng: 0, accuracyM: 5, ts: t0.add(Duration(seconds: sec)), source: PositionSource.gps, x: x, y: 0);
    test('every 2 s while moving, every 10 s while still', () {
      final p = SendPolicy();
      expect(p.shouldSend(at(0, 0)), isTrue);
      p.sent(at(0, 0));
      expect(p.shouldSend(at(1, 3)), isFalse);
      expect(p.shouldSend(at(2, 3)), isTrue);
      p.sent(at(2, 3));
      expect(p.shouldSend(at(9, 3.5)), isFalse);
      expect(p.shouldSend(at(12, 3.5)), isTrue);
    });
  });

  group('TrackingController.decide', () {
    SessionUser miner({Shift? shift = Shift.a}) => SessionUser(id: 'm1', role: Role.miner, fullName: 'M', employeeId: 'MIN-1', phoneE164: '', shift: shift);
    final inShift = DateTime(2026, 10, 17, 9, 0); // IST wall, shift A 06-14
    final offShift = DateTime(2026, 10, 17, 20, 0);
    test('miners only, consent first', () {
      expect(TrackingController.decide(user: null, consent: true, enabled: true, crisis: false, istWall: inShift), TrackingPhase.notMiner);
      final sup = SessionUser(id: 's', role: Role.supervisor, fullName: 'S', employeeId: 'S', phoneE164: '');
      expect(TrackingController.decide(user: sup, consent: true, enabled: true, crisis: true, istWall: inShift), TrackingPhase.notMiner);
      expect(TrackingController.decide(user: miner(), consent: null, enabled: true, crisis: false, istWall: inShift), TrackingPhase.needsConsent);
      expect(TrackingController.decide(user: miner(), consent: false, enabled: true, crisis: true, istWall: inShift), TrackingPhase.declined);
    });
    test('shift window ±30 min, off switch, crisis overrides both', () {
      expect(TrackingController.decide(user: miner(), consent: true, enabled: true, crisis: false, istWall: inShift), TrackingPhase.starting);
      expect(TrackingController.decide(user: miner(), consent: true, enabled: true, crisis: false, istWall: DateTime(2026, 10, 17, 14, 20)), TrackingPhase.starting);
      expect(TrackingController.decide(user: miner(), consent: true, enabled: true, crisis: false, istWall: offShift), TrackingPhase.outsideShift);
      expect(TrackingController.decide(user: miner(), consent: true, enabled: false, crisis: false, istWall: inShift), TrackingPhase.paused);
      expect(TrackingController.decide(user: miner(), consent: true, enabled: false, crisis: true, istWall: offShift), TrackingPhase.starting);
      expect(TrackingController.decide(user: miner(shift: null), consent: true, enabled: true, crisis: false, istWall: offShift), TrackingPhase.starting);
    });
  });
}
