import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

import '../../../contracts/enums.dart';
import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../data/profile_models.dart';
import '../data/profiles_repository.dart';

enum ProfilesStatus { loading, ready, failure }

class ProfilesState extends Equatable {
  const ProfilesState({
    this.status = ProfilesStatus.loading,
    this.items = const [],
    this.total = 0,
    this.query = '',
    this.roleTab,
    this.zoneId,
    this.band,
    this.pulse = const {},
    this.error,
  });

  final ProfilesStatus status;
  final List<ProfileCard> items;
  final int total;
  final String query;

  /// Admin tab (null = all roles).
  final Role? roleTab;
  final String? zoneId;

  /// Staff-only local filter on the risk band.
  final RiskBand? band;

  /// userId -> how many live updates arrived (drives the card pulse).
  final Map<String, int> pulse;
  final String? error;

  List<ProfileCard> get visible => band == null ? items : items.where((c) => c.riskBand == band).toList();

  int countBand(RiskBand b) => items.where((c) => c.riskBand == b).length;

  ProfilesState copyWith({ProfilesStatus? status, List<ProfileCard>? items, int? total, String? query, Role? roleTab, bool clearRole = false, String? zoneId, bool clearZone = false, RiskBand? band, bool clearBand = false, Map<String, int>? pulse, String? error, bool clearError = false}) =>
      ProfilesState(
        status: status ?? this.status,
        items: items ?? this.items,
        total: total ?? this.total,
        query: query ?? this.query,
        roleTab: clearRole ? null : (roleTab ?? this.roleTab),
        zoneId: clearZone ? null : (zoneId ?? this.zoneId),
        band: clearBand ? null : (band ?? this.band),
        pulse: pulse ?? this.pulse,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [status, items, total, query, roleTab, zoneId, band, pulse, error];
}

sealed class ProfilesEvent extends Equatable {
  const ProfilesEvent();
  @override
  List<Object?> get props => [];
}

class ProfilesStarted extends ProfilesEvent {
  const ProfilesStarted();
}

class ProfilesQueryChanged extends ProfilesEvent {
  const ProfilesQueryChanged(this.query);
  final String query;
  @override
  List<Object?> get props => [query];
}

class ProfilesRoleTabChanged extends ProfilesEvent {
  const ProfilesRoleTabChanged(this.role);
  final Role? role;
  @override
  List<Object?> get props => [role];
}

class ProfilesBandChanged extends ProfilesEvent {
  const ProfilesBandChanged(this.band);
  final RiskBand? band;
  @override
  List<Object?> get props => [band];
}

/// Live: one or more profiles changed (coalesced over 250 ms).
class _FlushChanged extends ProfilesEvent {
  const _FlushChanged();
}

class _Presence extends ProfilesEvent {
  const _Presence(this.byUser);
  final Map<String, Presence> byUser;
  @override
  List<Object?> get props => [byUser];
}

EventTransformer<E> _debounce<E>(Duration d) => (events, mapper) => events.debounceTime(d).switchMap(mapper);

/// Profile manager list (CLAUDE.md section 23.2). Live: `profile:updated` refetches only the changed cards,
/// `score:updated` / `leaderboard:updated` refresh the affected cards, `tracking:positions` moves presence dots.
class ProfilesBloc extends Bloc<ProfilesEvent, ProfilesState> {
  ProfilesBloc({required ProfilesRepository repo, required SocketService socket, required this.viewerId, required this.viewerRole})
      : _repo = repo,
        super(const ProfilesState()) {
    on<ProfilesStarted>(_load);
    on<ProfilesQueryChanged>((e, emit) async {
      emit(state.copyWith(query: e.query));
      await _load(const ProfilesStarted(), emit);
    }, transformer: _debounce(const Duration(milliseconds: 300)));
    on<ProfilesRoleTabChanged>((e, emit) async {
      emit(state.copyWith(roleTab: e.role, clearRole: e.role == null, clearBand: e.role != Role.miner, status: ProfilesStatus.loading));
      await _load(const ProfilesStarted(), emit);
    });
    on<ProfilesBandChanged>((e, emit) => emit(state.copyWith(band: e.band, clearBand: e.band == null || e.band == state.band)));
    on<_FlushChanged>(_flush, transformer: _debounce(const Duration(milliseconds: 250)));
    on<_Presence>((e, emit) {
      bool moved(ProfileCard c) => e.byUser[c.id] != null && e.byUser[c.id] != c.presence;
      if (!state.items.any(moved)) return;
      emit(state.copyWith(items: [for (final c in state.items) moved(c) ? c.withPresence(e.byUser[c.id]!) : c]));
    });

    _subs.add(socket.on(SocketEvents.profileUpdated).listen((env) => _mark('${env.data['userId']}')));
    _subs.add(socket.on(SocketEvents.scoreUpdated).listen((_) => _mark(viewerId)));
    _subs.add(socket.on(SocketEvents.leaderboardUpdated).listen((env) {
      for (final r in (env.data['top'] as List?) ?? const []) {
        final id = '${(r as Map)['userId']}';
        if (state.items.any((c) => c.id == id)) _mark(id);
      }
    }));
    _subs.add(socket.on(SocketEvents.trackingPositions).listen((env) {
      final m = <String, Presence>{};
      for (final p in (env.data['positions'] as List?) ?? const []) {
        try {
          m['${(p as Map)['userId']}'] = Presence.fromWire('${p['presence']}');
        } catch (_) {/* unknown value: ignore */}
      }
      if (m.isNotEmpty) add(_Presence(m));
    }));
  }

  final ProfilesRepository _repo;
  final String viewerId;
  final Role viewerRole;
  final _subs = <StreamSubscription<dynamic>>[];
  final _pending = <String>{};

  void _mark(String id) {
    if (id.isEmpty || isClosed) return;
    _pending.add(id);
    add(const _FlushChanged());
  }

  Future<void> _load(ProfilesStarted e, Emitter<ProfilesState> emit) async {
    try {
      final page = await _repo.list(role: viewerRole == Role.admin ? state.roleTab?.wire : null, q: state.query);
      emit(state.copyWith(status: ProfilesStatus.ready, items: _ordered(page.items), total: page.total, clearError: true));
    } on ApiException catch (x) {
      emit(state.copyWith(status: state.items.isEmpty ? ProfilesStatus.failure : ProfilesStatus.ready, error: x.message));
    }
  }

  /// Own card first, then supervisors, then by name.
  List<ProfileCard> _ordered(List<ProfileCard> items) {
    final list = [...items];
    int rank(ProfileCard c) => c.id == viewerId ? 0 : (c.role == Role.supervisor ? 1 : (c.role == Role.admin ? 2 : 3));
    list.sort((a, b) => rank(a).compareTo(rank(b)) != 0 ? rank(a).compareTo(rank(b)) : a.fullName.compareTo(b.fullName));
    return list;
  }

  Future<void> _flush(_FlushChanged e, Emitter<ProfilesState> emit) async {
    final ids = _pending.toList();
    _pending.clear();
    if (ids.isEmpty) return;
    final fresh = <String, ProfileCard?>{};
    await Future.wait(ids.map((id) async {
      try {
        fresh[id] = ProfileCard.fromDetail(await _repo.detail(id));
      } on ApiException catch (x) {
        if (x.statusCode == 403 || x.statusCode == 404) fresh[id] = null; // moved out of scope or removed
      }
    }));
    if (fresh.isEmpty) return;
    var items = [
      for (final c in state.items)
        if (!fresh.containsKey(c.id)) c else if (fresh[c.id] != null) fresh[c.id]!,
    ];
    final known = state.items.map((c) => c.id).toSet();
    final added = fresh.entries.where((x) => !known.contains(x.key) && x.value != null && _inTab(x.value!)).map((x) => x.value!);
    items = _ordered([...items, ...added]);
    final pulse = {...state.pulse};
    for (final id in fresh.keys) {
      pulse[id] = (pulse[id] ?? 0) + 1;
    }
    final removed = fresh.entries.where((x) => x.value == null && known.contains(x.key)).length;
    emit(state.copyWith(items: items, total: state.total - removed + added.length, pulse: pulse));
  }

  bool _inTab(ProfileCard c) => viewerRole != Role.admin || state.roleTab == null || state.roleTab == c.role;

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
