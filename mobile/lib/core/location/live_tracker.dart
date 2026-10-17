import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:uuid/uuid.dart';

import '../../contracts/socket_events.dart';
import '../db/layout_repository.dart';
import '../sensors/fusion_engine.dart';
import '../sensors/heading_filter.dart';
import '../sensors/local_frame.dart';
import '../sensors/map_matcher.dart';
import '../sensors/step_detector.dart';
import '../socket/socket_service.dart';
import '../sync/outbox_queue.dart';
import 'location_service.dart';

/// Live GPS + motion-sensor tracking (CLAUDE.md section 23.3).
/// geolocator position stream + sensors_plus (steps from the accelerometer, heading from gyro + magnetometer)
/// -> [FusionEngine] (Kalman, map-matched to the cached layout) -> `gps:update` every 2 s moving / 10 s still,
/// or the outbox (`gps`, 20 newest) while offline.
class LiveTracker {
  LiveTracker({required SocketService socket, required OutboxQueue queue, required LayoutRepository layouts, LocationService? location})
      : _socket = socket,
        _queue = queue,
        _layouts = layouts,
        _location = location ?? LocationService();

  final SocketService _socket;
  final OutboxQueue _queue;
  final LayoutRepository _layouts;
  final LocationService _location;

  final _fix = BehaviorSubject<FusedFix?>.seeded(null);
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _tick;
  FusionEngine? _engine;
  final _steps = StepDetector();
  final _heading = HeadingFilter();
  final _policy = SendPolicy();
  List<double>? _lastAccel;
  DateTime _lastMag = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sending = false;

  /// Latest fused position (null until the first fix).
  Stream<FusedFix?> get fix$ => _fix.stream;
  FusedFix? get lastFix => _fix.value;
  bool get running => _tick != null;

  Future<LocationAccess> start() async {
    if (running) return LocationAccess.granted;
    final access = await _location.ensurePermission();
    if (access != LocationAccess.granted) return access;
    final layout = await _layouts.cached();
    if (layout != null) {
      final frame = LocalFrame(layout.anchor.lat, layout.anchor.lng);
      _engine = FusionEngine(frame: frame, matcher: MapMatcher.fromLayout(layout, frame));
    }
    _subs.add(Geolocator.getPositionStream(locationSettings: _settings()).listen(_onPosition, onError: (_) {}));
    _listenSensors();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    return access;
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _fix.close();
  }

  LocationSettings _settings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Mine Guardian',
          notificationText: 'Mine Guardian is sharing your location for safety',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2);
  }

  void _onPosition(Position p) {
    final e = _engine ??= FusionEngine(frame: LocalFrame(p.latitude, p.longitude));
    final moving = p.speed > 0.5 && p.heading >= 0;
    e.addGps(lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy, ts: p.timestamp.toUtc(), speedMps: p.speed >= 0 ? p.speed : null, headingDeg: moving ? p.heading : null);
  }

  void _listenSensors() {
    // Sensors are missing on some devices / browsers: tracking falls back to GPS only.
    _subs.add(accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((a) {
      _lastAccel = [a.x, a.y, a.z];
      final len = _steps.add(a.x, a.y, a.z, a.timestamp);
      if (len != null) _engine?.addStep(len, a.timestamp.toUtc());
    }, onError: (_) {}));
    _subs.add(gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen((g) {
      _heading.addGyro(g.z, g.timestamp);
      _engine?.setHeading(_heading.headingDeg);
    }, onError: (_) {}));
    _subs.add(magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((m) {
      final a = _lastAccel;
      if (a == null || m.timestamp.difference(_lastMag) < const Duration(milliseconds: 200)) return;
      _lastMag = m.timestamp;
      final h = HeadingFilter.tiltCompensated(a[0], a[1], a[2], m.x, m.y, m.z);
      if (h != null) _heading.addMag(h);
      _engine?.setHeading(_heading.headingDeg);
    }, onError: (_) {}));
  }

  Future<void> _onTick() async {
    final e = _engine;
    if (e == null || !e.hasFix) return;
    final f = e.current(DateTime.now().toUtc());
    if (f == null) return;
    _fix.add(f);
    if (_sending || !_policy.shouldSend(f)) return;
    _sending = true;
    try {
      final data = f.toGpsUpdate();
      if (_socket.isConnected) {
        final ack = await _socket.emit(SocketEvents.gpsUpdate, data);
        if (ack == null) await _queue.enqueueGps(clientId: const Uuid().v4(), payload: data);
      } else {
        await _queue.enqueueGps(clientId: const Uuid().v4(), payload: data);
      }
      _policy.sent(f);
    } catch (_) {
      // next tick retries
    } finally {
      _sending = false;
    }
  }
}
