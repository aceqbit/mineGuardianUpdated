import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../contracts/enums.dart';
import '../../../core/models/mine_layout.dart';
import '../../sos/data/evac_graph.dart';
import '../data/live_map_repository.dart';
import '../data/route_modes.dart';

enum LiveMapStatus { loading, noLayout, ready }

/// A position farther than this from every junction is not inside the mine (e.g. testing at home).
const double outsideMineM = 250;

/// Leaving the selected route by more than this re-plans it.
const double offRouteM = 15;

class LiveMapState extends Equatable {
  const LiveMapState({
    this.status = LiveMapStatus.loading,
    this.layout,
    this.planner,
    this.hazards = const [],
    this.fix,
    this.pinnedStart,
    this.target,
    this.routes = const [],
    this.selectedKey,
    this.startNode,
    this.outsideMine = false,
    this.arrived = false,
    this.replans = 0,
  });

  final LiveMapStatus status;
  final MineLayoutData? layout;
  final RoutePlanner? planner;
  final List<RouteHazard> hazards;
  final MapFix? fix;
  final GeoPoint? pinnedStart;
  final RouteTarget? target;
  final List<ModeRoute> routes;
  final String? selectedKey;
  final String? startNode;

  /// The live position is far from the mine: routes start from a pinned point (or wait for one).
  final bool outsideMine;
  final bool arrived;

  /// How many times the route was re-planned automatically (off route, new hazard, new start junction).
  final int replans;

  ModeRoute? get selected => routes.where((r) => r.key == selectedKey).firstOrNull ?? routes.firstOrNull;

  LiveMapState copyWith({
    LiveMapStatus? status,
    MineLayoutData? layout,
    RoutePlanner? planner,
    List<RouteHazard>? hazards,
    MapFix? fix,
    GeoPoint? pinnedStart,
    bool clearPinned = false,
    RouteTarget? target,
    bool clearTarget = false,
    List<ModeRoute>? routes,
    String? selectedKey,
    String? startNode,
    bool? outsideMine,
    bool? arrived,
    int? replans,
  }) =>
      LiveMapState(
        status: status ?? this.status,
        layout: layout ?? this.layout,
        planner: planner ?? this.planner,
        hazards: hazards ?? this.hazards,
        fix: fix ?? this.fix,
        pinnedStart: clearPinned ? null : (pinnedStart ?? this.pinnedStart),
        target: clearTarget ? null : (target ?? this.target),
        routes: routes ?? this.routes,
        selectedKey: selectedKey ?? this.selectedKey,
        startNode: startNode ?? this.startNode,
        outsideMine: outsideMine ?? this.outsideMine,
        arrived: arrived ?? this.arrived,
        replans: replans ?? this.replans,
      );

  @override
  List<Object?> get props => [status, layout?.version, planner, hazards.length, fix?.ts, fix?.lat, fix?.lng, pinnedStart, target?.id, routes, selectedKey, startNode, outsideMine, arrived, replans];
}

sealed class LiveMapEvent extends Equatable {
  const LiveMapEvent();
  @override
  List<Object?> get props => [];
}

class LiveMapStarted extends LiveMapEvent {
  const LiveMapStarted();
}

class LiveMapFixArrived extends LiveMapEvent {
  const LiveMapFixArrived(this.fix);
  final MapFix fix;
  @override
  List<Object?> get props => [fix.ts, fix.lat, fix.lng];
}

class LiveMapTargetChosen extends LiveMapEvent {
  const LiveMapTargetChosen(this.targetId);
  final String? targetId;
  @override
  List<Object?> get props => [targetId];
}

/// Long-press: route to the junction nearest this point.
class LiveMapPointChosen extends LiveMapEvent {
  const LiveMapPointChosen(this.point);
  final GeoPoint point;
  @override
  List<Object?> get props => [point.lat, point.lng];
}

class LiveMapStartPinned extends LiveMapEvent {
  const LiveMapStartPinned(this.point);
  final GeoPoint? point;
  @override
  List<Object?> get props => [point?.lat, point?.lng];
}

class LiveMapRouteSelected extends LiveMapEvent {
  const LiveMapRouteSelected(this.key);
  final String key;
  @override
  List<Object?> get props => [key];
}

class LiveMapHazardsRefreshed extends LiveMapEvent {
  const LiveMapHazardsRefreshed();
}

/// The miner's own live map (CLAUDE.md section 23.4): set a destination, four route modes, re-planned as you move.
class LiveMapBloc extends Bloc<LiveMapEvent, LiveMapState> {
  LiveMapBloc({required LiveMapRepository repo, required Stream<MapFix> positions, Duration hazardEvery = const Duration(seconds: 30)})
      : _repo = repo,
        super(const LiveMapState()) {
    on<LiveMapStarted>(_start);
    on<LiveMapFixArrived>(_onFix);
    on<LiveMapTargetChosen>((e, emit) {
      final t = e.targetId == null ? null : state.planner?.target(e.targetId!);
      _replan(emit, state.copyWith(target: t, clearTarget: t == null, arrived: false), keepSelection: false);
    });
    on<LiveMapPointChosen>((e, emit) {
      final t = state.planner?.targetNear(e.point);
      if (t != null) _replan(emit, state.copyWith(target: t, arrived: false), keepSelection: false);
    });
    on<LiveMapStartPinned>((e, emit) => _replan(emit, state.copyWith(pinnedStart: e.point, clearPinned: e.point == null), keepSelection: false));
    on<LiveMapRouteSelected>((e, emit) => emit(state.copyWith(selectedKey: e.key)));
    on<LiveMapHazardsRefreshed>(_refreshHazards);
    _sub = positions.listen((f) => add(LiveMapFixArrived(f)), onError: (_) {});
    _hazardTimer = Timer.periodic(hazardEvery, (_) => add(const LiveMapHazardsRefreshed()));
  }

  final LiveMapRepository _repo;
  StreamSubscription<MapFix>? _sub;
  Timer? _hazardTimer;

  Future<void> _start(LiveMapStarted e, Emitter<LiveMapState> emit) async {
    final layout = await _repo.layout();
    if (layout == null) return emit(state.copyWith(status: LiveMapStatus.noLayout));
    final hazards = await _repo.hazards();
    final planner = RoutePlanner.build(layout, hazards: hazards);
    var s = state.copyWith(status: LiveMapStatus.ready, layout: layout, hazards: hazards, planner: planner);
    // A fix that arrived while the layout was loading is judged now that the mine is known.
    final early = s.fix;
    if (early != null) s = s.copyWith(outsideMine: _outside(s, early.point));
    // Default destination: the nearest reachable exit by the hindrance-aware cost.
    s = s.copyWith(target: s.target ?? _nearestExit(s, planner));
    _replan(emit, s, keepSelection: false);
  }

  RouteTarget? _nearestExit(LiveMapState s, RoutePlanner p) {
    final start = _startNode(s);
    if (start == null) return null;
    ModeRoute? best;
    for (final t in p.targets.where((t) => t.kind == TargetKind.exit)) {
      final r = p.route(start, t, _defaultMode);
      if (r != null && (best == null || r.cost < best.cost)) best = r;
    }
    return best?.target;
  }

  static const _defaultMode = RouteMode.leastHindrance;

  String? _startNode(LiveMapState s) {
    final p = s.planner;
    if (p == null) return null;
    if (s.pinnedStart != null) return p.nearestJunction(s.pinnedStart!);
    final f = s.fix;
    if (f == null || _outside(s, f.point)) return null;
    return p.nearestJunction(f.point);
  }

  bool _outside(LiveMapState s, GeoPoint at) {
    final l = s.layout;
    if (l == null || l.junctions.isEmpty) return true;
    var best = double.infinity;
    for (final j in l.junctions) {
      final d = haversineM(at, j.point);
      if (d < best) best = d;
    }
    return best > outsideMineM;
  }

  void _replan(Emitter<LiveMapState> emit, LiveMapState s, {required bool keepSelection, bool auto = false}) {
    final p = s.planner;
    final start = _startNode(s);
    if (p == null || start == null || s.target == null) {
      emit(s.copyWith(routes: const [], startNode: start));
      return;
    }
    final routes = p.plan(start, s.target!);
    final prevMode = s.selected?.primary;
    String? key;
    if (keepSelection && prevMode != null) key = routes.where((r) => r.modes.contains(prevMode)).firstOrNull?.key;
    key ??= routes.firstOrNull?.key;
    emit(s.copyWith(routes: routes, selectedKey: key, startNode: start, replans: auto ? s.replans + 1 : s.replans));
  }

  void _onFix(LiveMapFixArrived e, Emitter<LiveMapState> emit) {
    final outside = state.layout != null && _outside(state, e.fix.point);
    var s = state.copyWith(fix: e.fix, outsideMine: outside);
    if (s.status != LiveMapStatus.ready) return emit(s);
    final t = s.target;
    if (t != null && !outside && haversineM(e.fix.point, t.point) < 10) s = s.copyWith(arrived: true);
    if (s.target == null && s.planner != null) s = s.copyWith(target: _nearestExit(s, s.planner!));
    final sel = s.selected;
    final newStart = _startNode(s);
    final off = sel != null && s.pinnedStart == null && !outside && EvacGraph.distanceToRouteM(e.fix.point, sel.asEvacRoute) > offRouteM;
    if (s.routes.isEmpty || off || (s.pinnedStart == null && newStart != s.startNode)) {
      _replan(emit, s, keepSelection: true, auto: s.routes.isNotEmpty);
    } else {
      emit(s);
    }
  }

  Future<void> _refreshHazards(LiveMapHazardsRefreshed e, Emitter<LiveMapState> emit) async {
    final layout = state.layout;
    if (layout == null) return;
    final hazards = await _repo.hazards();
    final planner = RoutePlanner.build(layout, hazards: hazards);
    final changed = planner.closed.length != (state.planner?.closed.length ?? 0) || !planner.closed.containsAll(state.planner?.closed ?? const {}) || hazards.length != state.hazards.length;
    final s = state.copyWith(hazards: hazards, planner: planner);
    if (changed) {
      _replan(emit, s, keepSelection: true, auto: true);
    } else {
      emit(s);
    }
  }

  @override
  Future<void> close() async {
    _hazardTimer?.cancel();
    await _sub?.cancel();
    return super.close();
  }
}

