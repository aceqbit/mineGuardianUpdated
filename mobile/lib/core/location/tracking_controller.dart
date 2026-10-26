import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:rxdart/rxdart.dart';

import '../../contracts/enums.dart';
import '../../contracts/socket_events.dart';
import '../api/api_client.dart';
import '../auth/session_bloc.dart';
import '../db/cache_repository.dart';
import '../models/session_user.dart';
import '../sensors/fusion_engine.dart';
import '../socket/socket_service.dart';
import '../time/ist.dart';
import 'live_tracker.dart';
import 'location_service.dart';

enum TrackingPhase { notMiner, needsConsent, declined, paused, outsideShift, starting, live, denied }

class TrackingStatus extends Equatable {
  const TrackingStatus({required this.phase, this.crisis = false, this.fix});
  final TrackingPhase phase;

  /// A crisis is active: tracking runs regardless of the off switch and the shift window.
  final bool crisis;
  final FusedFix? fix;

  PositionSource? get source => fix?.source;

  @override
  List<Object?> get props => [phase, crisis, fix?.ts, fix?.source];
}

/// Decides when [LiveTracker] runs (CLAUDE.md section 23.3): miners only, after consent, inside their shift window
/// (±30 min IST, or always when no shift is set), unless switched off; during a crisis it always runs.
class TrackingController {
  TrackingController({required SessionBloc session, required LiveTracker tracker, required CacheRepository cache, required SocketService socket, ApiClient? api})
      : _session = session,
        _tracker = tracker,
        _cache = cache,
        _socket = socket,
        _api = api;

  final SessionBloc _session;
  final LiveTracker _tracker;
  final CacheRepository _cache;
  final SocketService _socket;
  final ApiClient? _api;

  final _status = BehaviorSubject<TrackingStatus>.seeded(const TrackingStatus(phase: TrackingPhase.notMiner));
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _every;
  SessionUser? _user;
  bool? _consent;
  bool _enabled = true;
  bool _crisis = false;
  bool _evaluating = false;

  Stream<TrackingStatus> get status$ => _status.stream.distinct();
  TrackingStatus get status => _status.value;

  void start() {
    _subs.add(_session.stream.startWith(_session.state).listen(_onSession));
    _subs.add(_socket.on(SocketEvents.crisisActivated).listen((_) => _setCrisis(true)));
    _subs.add(_socket.on(SocketEvents.crisisResolved).listen((_) => _setCrisis(false)));
    _subs.add(_tracker.fix$.listen((f) {
      if (_tracker.running) _status.add(TrackingStatus(phase: TrackingPhase.live, crisis: _crisis, fix: f));
    }));
    _every = Timer.periodic(const Duration(minutes: 1), (_) => _evaluate());
  }

  Future<void> grantConsent() async {
    _consent = true;
    await _cache.write(CacheKeys.trackingConsent, {'granted': true, 'at': DateTime.now().toUtc().toIso8601String()});
    await _evaluate();
  }

  Future<void> declineConsent() async {
    _consent = false;
    await _cache.write(CacheKeys.trackingConsent, {'granted': false, 'at': DateTime.now().toUtc().toIso8601String()});
    await _evaluate();
  }

  /// The miner's off switch (ignored while a crisis is active).
  Future<void> setEnabled(bool on) async {
    _enabled = on;
    await _cache.write(CacheKeys.trackingEnabled, on);
    await _evaluate();
  }

  Future<void> _onSession(SessionState s) async {
    _user = s is SessionAuthenticated ? s.user : null;
    if (_user?.role == Role.miner) {
      final c = await _cache.read(CacheKeys.trackingConsent);
      _consent = c is Map ? c['granted'] == true : null;
      final en = await _cache.read(CacheKeys.trackingEnabled);
      _enabled = en is bool ? en : true;
      await _checkCrisis();
    }
    await _evaluate();
  }

  Future<void> _checkCrisis() async {
    final api = _api;
    if (api == null) return;
    try {
      final j = await api.getJson('/api/crisis/active');
      _crisis = j['active'] == true;
    } catch (_) {/* offline or not available yet: keep the last known state */}
  }

  Future<void> _setCrisis(bool on) async {
    _crisis = on;
    await _evaluate();
  }

  /// Pure decision, exposed for tests.
  static TrackingPhase decide({required SessionUser? user, required bool? consent, required bool enabled, required bool crisis, required DateTime istWall}) {
    if (user == null || user.role != Role.miner) return TrackingPhase.notMiner;
    if (consent == null) return TrackingPhase.needsConsent;
    if (consent == false) return TrackingPhase.declined;
    if (crisis) return TrackingPhase.starting;
    if (!enabled) return TrackingPhase.paused;
    final shift = user.shift;
    if (shift != null && !isShiftOpen(shift, istWall, toleranceMin: 30)) return TrackingPhase.outsideShift;
    return TrackingPhase.starting;
  }

  Future<void> _evaluate() async {
    if (_evaluating) return;
    _evaluating = true;
    try {
      final phase = decide(user: _user, consent: _consent, enabled: _enabled, crisis: _crisis, istWall: nowIst());
      if (phase != TrackingPhase.starting) {
        await _tracker.stop();
        _status.add(TrackingStatus(phase: phase, crisis: _crisis));
        return;
      }
      if (_tracker.running) {
        _status.add(TrackingStatus(phase: TrackingPhase.live, crisis: _crisis, fix: _tracker.lastFix));
        return;
      }
      _status.add(TrackingStatus(phase: TrackingPhase.starting, crisis: _crisis));
      final access = await _tracker.start();
      _status.add(TrackingStatus(phase: access == LocationAccess.granted ? TrackingPhase.live : TrackingPhase.denied, crisis: _crisis, fix: _tracker.lastFix));
    } finally {
      _evaluating = false;
    }
  }

  Future<void> dispose() async {
    _every?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _tracker.dispose();
    await _status.close();
  }
}
