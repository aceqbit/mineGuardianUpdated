import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../contracts/enums.dart';
import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/mine_layout.dart';
import '../../../core/socket/socket_service.dart';
import '../../profiles/data/profile_models.dart';
import '../../profiles/data/profiles_repository.dart';
import '../data/live_map_repository.dart';

/// Trail length shown behind each moving person.
const Duration trailWindow = Duration(seconds: 60);

class FleetPerson extends Equatable {
  const FleetPerson({required this.now, required this.trail});
  final FleetPosition now;

  /// Recent positions, oldest first, within [trailWindow].
  final List<(GeoPoint, DateTime)> trail;

  @override
  List<Object?> get props => [now.userId, now.fix.ts, now.fix.lat, now.fix.lng, now.presence, trail.length];
}

enum FleetStatus { loading, noLayout, ready, failure }

class FleetState extends Equatable {
  const FleetState({this.status = FleetStatus.loading, this.layout, this.people = const {}, this.zoneId, this.selectedId, this.selectedProfile, this.batch = 0, this.error});
  final FleetStatus status;
  final MineLayoutData? layout;
  final Map<String, FleetPerson> people;

  /// Admin zone filter (null = whole mine).
  final String? zoneId;
  final String? selectedId;
  final ProfileCard? selectedProfile;

  /// Bumped on every position batch (drives the marker tween).
  final int batch;
  final String? error;

  List<FleetPerson> get visible {
    final list = people.values.where((p) => zoneId == null || p.now.zoneId == zoneId).toList();
    int rank(FleetPerson p) => p.now.sosId != null ? 0 : switch (p.now.presence) { Presence.live => 1, Presence.stale => 2, Presence.offline => 3 };
    list.sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.now.name.compareTo(b.now.name));
    return list;
  }

  int count(Presence p) => visible.where((x) => x.now.presence == p).length;

  FleetState copyWith({FleetStatus? status, MineLayoutData? layout, Map<String, FleetPerson>? people, String? zoneId, bool clearZone = false, String? selectedId, bool clearSelected = false, ProfileCard? selectedProfile, int? batch, String? error}) => FleetState(
        status: status ?? this.status,
        layout: layout ?? this.layout,
        people: people ?? this.people,
        zoneId: clearZone ? null : (zoneId ?? this.zoneId),
        selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
        selectedProfile: clearSelected ? null : (selectedProfile ?? this.selectedProfile),
        batch: batch ?? this.batch,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [status, layout?.version, people, zoneId, selectedId, selectedProfile, batch, error];
}

sealed class FleetEvent extends Equatable {
  const FleetEvent();
  @override
  List<Object?> get props => [];
}

class FleetStarted extends FleetEvent {
  const FleetStarted();
}

class FleetZoneChanged extends FleetEvent {
  const FleetZoneChanged(this.zoneId);
  final String? zoneId;
  @override
  List<Object?> get props => [zoneId];
}

class FleetPersonSelected extends FleetEvent {
  const FleetPersonSelected(this.userId);
  final String? userId;
  @override
  List<Object?> get props => [userId];
}

class _Batch extends FleetEvent {
  const _Batch(this.positions);
  final List<FleetPosition> positions;
  @override
  List<Object?> get props => [positions.length, positions.firstOrNull?.fix.ts];
}

/// Admin / supervisor live map (CLAUDE.md section 23.4): everyone the server lets this viewer see, moving in real time.
class FleetBloc extends Bloc<FleetEvent, FleetState> {
  FleetBloc({required LiveMapRepository repo, required ProfilesRepository profiles, required SocketService socket})
      : _repo = repo,
        _profiles = profiles,
        super(const FleetState()) {
    on<FleetStarted>((e, emit) async {
      final layout = await _repo.layout();
      if (layout == null) return emit(state.copyWith(status: FleetStatus.noLayout));
      try {
        final snap = await _repo.fleet();
        emit(state.copyWith(status: FleetStatus.ready, layout: layout, people: _merge(state.people, snap), batch: state.batch + 1));
      } on ApiException catch (x) {
        emit(state.copyWith(status: FleetStatus.ready, layout: layout, error: x.message));
      }
    });
    on<_Batch>((e, emit) => emit(state.copyWith(people: _merge(state.people, e.positions), batch: state.batch + 1)));
    on<FleetZoneChanged>((e, emit) => emit(state.copyWith(zoneId: e.zoneId, clearZone: e.zoneId == null)));
    on<FleetPersonSelected>((e, emit) async {
      if (e.userId == null) return emit(state.copyWith(clearSelected: true));
      emit(state.copyWith(selectedId: e.userId, clearSelected: false));
      try {
        final d = await _profiles.detail(e.userId!);
        if (state.selectedId == e.userId) emit(state.copyWith(selectedProfile: ProfileCard.fromDetail(d)));
      } on ApiException {
        // the sheet shows what the position carries
      }
    });
    _sub = socket.on(SocketEvents.trackingPositions).listen((env) {
      final list = ((env.data['positions'] as List?) ?? const []).map((p) => FleetPosition.fromJson((p as Map).cast<String, dynamic>())).whereType<FleetPosition>().toList();
      if (list.isNotEmpty) add(_Batch(list));
    });
  }

  final LiveMapRepository _repo;
  final ProfilesRepository _profiles;
  StreamSubscription<dynamic>? _sub;

  /// Applies a batch: newer fixes replace older ones, each person keeps a [trailWindow] trail.
  static Map<String, FleetPerson> merge(Map<String, FleetPerson> people, List<FleetPosition> batch) => _merge(people, batch);

  static Map<String, FleetPerson> _merge(Map<String, FleetPerson> people, List<FleetPosition> batch) {
    final out = {...people};
    for (final p in batch) {
      final prev = out[p.userId];
      if (prev != null && prev.now.fix.ts.isAfter(p.fix.ts)) continue; // out of order
      final moved = prev == null || prev.now.fix.lat != p.fix.lat || prev.now.fix.lng != p.fix.lng;
      final trail = [
        ...?prev?.trail.where((t) => p.fix.ts.difference(t.$2) <= trailWindow),
        if (moved) (p.fix.point, p.fix.ts),
      ];
      out[p.userId] = FleetPerson(now: p, trail: trail);
    }
    return out;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
