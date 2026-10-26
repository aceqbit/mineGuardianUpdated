import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../contracts/enums.dart';
import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/location/tracking_controller.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/sync/sync_engine.dart';

class DockState extends Equatable {
  const DockState({this.online = false, this.pending = 0, this.failed = 0, this.tracking, this.source, this.crisis});
  final bool online;
  final int pending;
  final int failed;
  final TrackingPhase? tracking;
  final PositionSource? source;

  /// null = not known yet.
  final bool? crisis;

  DockState copyWith({bool? online, int? pending, int? failed, TrackingPhase? tracking, PositionSource? source, bool clearSource = false, bool? crisis}) => DockState(
        online: online ?? this.online,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        tracking: tracking ?? this.tracking,
        source: clearSource ? null : (source ?? this.source),
        crisis: crisis ?? this.crisis,
      );

  @override
  List<Object?> get props => [online, pending, failed, tracking, source, crisis];
}

sealed class DockEvent {
  const DockEvent();
}

class DockStarted extends DockEvent {
  const DockStarted();
}

class _Online extends DockEvent {
  const _Online(this.v);
  final bool v;
}

class _Outbox extends DockEvent {
  const _Outbox(this.pending, this.failed);
  final int pending, failed;
}

class _Tracking extends DockEvent {
  const _Tracking(this.status);
  final TrackingStatus status;
}

class _Crisis extends DockEvent {
  const _Crisis(this.active);
  final bool active;
}

/// Live status for the feature dock (CLAUDE.md section 23.7): socket, outbox, tracking source, crisis.
class FeatureDockBloc extends Bloc<DockEvent, DockState> {
  FeatureDockBloc({required SocketService socket, SyncEngine? engine, TrackingController? tracking, ApiClient? api})
      : _socket = socket,
        _engine = engine,
        _tracking = tracking,
        _api = api,
        super(DockState(online: socket.isConnected)) {
    on<DockStarted>((e, emit) async {
      final api = _api;
      if (api == null) return;
      try {
        add(_Crisis((await api.getJson('/api/crisis/active'))['active'] == true));
      } catch (_) {/* offline: unknown until an event arrives */}
    });
    on<_Online>((e, emit) => emit(state.copyWith(online: e.v)));
    on<_Outbox>((e, emit) => emit(state.copyWith(pending: e.pending, failed: e.failed)));
    on<_Tracking>((e, emit) => emit(state.copyWith(tracking: e.status.phase, source: e.status.source, clearSource: e.status.source == null, crisis: e.status.crisis ? true : null)));
    on<_Crisis>((e, emit) => emit(state.copyWith(crisis: e.active)));
    _subs.add(_socket.connection$.listen((v) => add(_Online(v))));
    _subs.add(_socket.on(SocketEvents.crisisActivated).listen((_) => add(const _Crisis(true))));
    _subs.add(_socket.on(SocketEvents.crisisResolved).listen((_) => add(const _Crisis(false))));
    final eng = _engine;
    if (eng != null) {
      add(_Outbox(eng.status.pendingCount, eng.status.failedCount));
      _subs.add(eng.status$.listen((s) => add(_Outbox(s.pendingCount, s.failedCount))));
    }
    final tr = _tracking;
    if (tr != null) {
      add(_Tracking(tr.status));
      _subs.add(tr.status$.listen((s) => add(_Tracking(s))));
    }
  }

  final SocketService _socket;
  final SyncEngine? _engine;
  final TrackingController? _tracking;
  final ApiClient? _api;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
