import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../contracts/enums.dart';
import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../data/crisis_models.dart';
import '../data/crisis_repository.dart';

enum CrisisPhase { idle, active, resolved }

class CrisisState extends Equatable {
  const CrisisState({
    this.phase = CrisisPhase.idle,
    this.crisis,
    this.roster = const [],
    this.positions = const {},
    this.routes = const [],
    this.activationSeq = 0,
    this.falseAlarm = false,
    this.resolvedAt,
    this.busy = false,
    this.notice,
    this.noticeIsError = false,
    this.report,
  });

  final CrisisPhase phase;
  final CrisisInfo? crisis;
  final List<RosterRow> roster;
  final Map<String, CrisisPosition> positions;
  final List<CrisisRoute> routes;

  /// Increments on every NEW activation so overlays fire exactly once per crisis.
  final int activationSeq;
  final bool falseAlarm;
  final DateTime? resolvedAt;
  final bool busy;
  final String? notice;
  final bool noticeIsError;
  final Map<String, dynamic>? report;

  bool get isActive => phase == CrisisPhase.active;

  Map<AccountedStatus, int> get counts {
    final m = {for (final s in AccountedStatus.values) s: 0};
    for (final r in roster) {
      m[r.status] = (m[r.status] ?? 0) + 1;
    }
    return m;
  }

  bool get allAccounted => roster.isNotEmpty && roster.every((r) => r.status != AccountedStatus.unknown && r.status != AccountedStatus.missing);

  CrisisState copyWith({CrisisPhase? phase, CrisisInfo? crisis, List<RosterRow>? roster, Map<String, CrisisPosition>? positions, List<CrisisRoute>? routes, int? activationSeq, bool? falseAlarm, DateTime? resolvedAt, bool? busy, String? notice, bool noticeIsError = false, bool clearNotice = false, Map<String, dynamic>? report}) => CrisisState(
        phase: phase ?? this.phase,
        crisis: crisis ?? this.crisis,
        roster: roster ?? this.roster,
        positions: positions ?? this.positions,
        routes: routes ?? this.routes,
        activationSeq: activationSeq ?? this.activationSeq,
        falseAlarm: falseAlarm ?? this.falseAlarm,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        busy: busy ?? this.busy,
        notice: clearNotice ? null : (notice ?? this.notice),
        noticeIsError: clearNotice ? false : (notice != null ? noticeIsError : this.noticeIsError),
        report: report ?? this.report,
      );

  @override
  List<Object?> get props => [phase, crisis, roster, positions, routes, activationSeq, falseAlarm, resolvedAt, busy, notice, noticeIsError, report];
}

sealed class CrisisEvent extends Equatable {
  const CrisisEvent();
  @override
  List<Object?> get props => [];
}

class CrisisStarted extends CrisisEvent {
  const CrisisStarted();
}

class CrisisSocketEvent extends CrisisEvent {
  const CrisisSocketEvent(this.event, this.data);
  final String event;
  final Map<String, dynamic> data;
  @override
  List<Object?> get props => [event, data];
}

class CrisisActivateRequested extends CrisisEvent {
  const CrisisActivateRequested(this.zoneIds, this.reason);
  final List<String> zoneIds;
  final String reason;
  @override
  List<Object?> get props => [zoneIds, reason];
}

class CrisisResolveRequested extends CrisisEvent {
  const CrisisResolveRequested({required this.falseAlarm, required this.note, required this.allAccounted, required this.hazardsContained});
  final bool falseAlarm, allAccounted, hazardsContained;
  final String note;
  @override
  List<Object?> get props => [falseAlarm, note, allAccounted, hazardsContained];
}

class CrisisAccountedSet extends CrisisEvent {
  const CrisisAccountedSet(this.workerId, this.status);
  final String workerId;
  final AccountedStatus status;
  @override
  List<Object?> get props => [workerId, status];
}

class CrisisEdgeToggled extends CrisisEvent {
  const CrisisEdgeToggled(this.edgeId, this.blocked);
  final String edgeId;
  final bool blocked;
  @override
  List<Object?> get props => [edgeId, blocked];
}

class CrisisRouteAssignRequested extends CrisisEvent {
  const CrisisRouteAssignRequested(this.workerId, this.exitId);
  final String workerId, exitId;
  @override
  List<Object?> get props => [workerId, exitId];
}

class CrisisRecomputeRequested extends CrisisEvent {
  const CrisisRecomputeRequested();
}

class CrisisReportRequested extends CrisisEvent {
  const CrisisReportRequested();
}

class CrisisNoticeShown extends CrisisEvent {
  const CrisisNoticeShown();
}

class CrisisCleared extends CrisisEvent {
  const CrisisCleared();
}

/// App-wide crisis state. Every client hears `crisis:activated` / `crisis:resolved`; staff also get the roster, positions and routes.
class CrisisBloc extends Bloc<CrisisEvent, CrisisState> {
  CrisisBloc({required CrisisRepository repo, required SocketService socket, required bool Function() isStaff}) : _repo = repo, _isStaff = isStaff, super(const CrisisState()) {
    on<CrisisStarted>(_start);
    on<CrisisSocketEvent>(_onSocket);
    on<CrisisActivateRequested>((e, emit) => _run(emit, () => _repo.activate(e.zoneIds, e.reason), ok: 'Crisis mode activated'));
    on<CrisisResolveRequested>((e, emit) async {
      final id = state.crisis?.id;
      if (id == null) return;
      await _run(emit, () => _repo.resolve(id, falseAlarm: e.falseAlarm, note: e.note, allAccounted: e.allAccounted, hazardsContained: e.hazardsContained), ok: 'Crisis resolved');
    });
    on<CrisisAccountedSet>((e, emit) async {
      final id = state.crisis?.id;
      if (id == null) return;
      final before = state.roster;
      emit(state.copyWith(roster: [for (final r in before) r.userId == e.workerId ? r.withStatus(e.status) : r]));
      try {
        await _repo.setAccounted(id, e.workerId, e.status);
      } on ApiException catch (ex) {
        emit(state.copyWith(roster: before, notice: ex.message, noticeIsError: true));
      }
    });
    on<CrisisEdgeToggled>((e, emit) async {
      final id = state.crisis?.id;
      if (id == null) return;
      await _run(emit, () => _repo.blockEdge(id, e.edgeId, e.blocked), ok: e.blocked ? 'Tunnel blocked, routes updated' : 'Tunnel reopened, routes updated', then: () => _refresh(emit));
    });
    on<CrisisRouteAssignRequested>((e, emit) async {
      final id = state.crisis?.id;
      if (id == null) return;
      await _run(emit, () => _repo.assignRoute(id, e.workerId, e.exitId), ok: 'Route sent to the worker');
    });
    on<CrisisRecomputeRequested>((e, emit) async {
      final id = state.crisis?.id;
      if (id == null) return;
      await _run(emit, () => _repo.recompute(id), ok: 'Routes recomputed');
    });
    on<CrisisReportRequested>((e, emit) async {
      final id = state.crisis?.id;
      if (id == null) return;
      try {
        emit(state.copyWith(report: await _repo.report(id)));
      } on ApiException {
        emit(state.copyWith(notice: 'The report is not ready yet', noticeIsError: true));
      }
    });
    on<CrisisNoticeShown>((e, emit) => emit(state.copyWith(clearNotice: true)));
    on<CrisisCleared>((e, emit) => emit(CrisisState(activationSeq: state.activationSeq)));
    for (final ev in [SocketEvents.crisisActivated, SocketEvents.crisisUpdated, SocketEvents.crisisPositions, SocketEvents.crisisRoutes, SocketEvents.crisisResolved]) {
      _subs.add(socket.on(ev).listen((env) => add(CrisisSocketEvent(ev, env.data))));
    }
  }

  final CrisisRepository _repo;
  final bool Function() _isStaff;
  final _subs = <StreamSubscription<dynamic>>[];

  Future<void> _run(Emitter<CrisisState> emit, Future<void> Function() action, {required String ok, Future<void> Function()? then}) async {
    emit(state.copyWith(busy: true, clearNotice: true));
    try {
      await action();
      emit(state.copyWith(busy: false, notice: ok));
      await then?.call();
    } on ApiException catch (ex) {
      emit(state.copyWith(busy: false, notice: ex.message, noticeIsError: true));
    }
  }

  Future<void> _start(CrisisStarted e, Emitter<CrisisState> emit) async {
    try {
      final d = await _repo.active();
      if (!d.active) return;
      // A crisis found at start-up or login shows the banner only. Forced navigation, siren and flash are for a crisis
      // that activates live (socket), otherwise every login would bounce the user to the evacuation screen.
      emit(_applyActive(d, activate: false));
    } on ApiException {
      // not signed in yet or offline: the socket will tell us
    }
  }

  Future<void> _refresh(Emitter<CrisisState> emit) async {
    try {
      final d = await _repo.active();
      if (d.active) emit(_applyActive(d, activate: false));
    } on ApiException {
      // keep the current picture
    }
  }

  CrisisState _applyActive(ActiveCrisisData d, {required bool activate}) => state.copyWith(
        phase: CrisisPhase.active,
        crisis: d.crisis,
        roster: d.roster.isEmpty ? state.roster : d.roster,
        positions: d.positions.isEmpty ? state.positions : {for (final p in d.positions) p.userId: p},
        routes: d.routes.isEmpty ? state.routes : d.routes,
        activationSeq: activate ? state.activationSeq + 1 : state.activationSeq,
      );

  Future<void> _onSocket(CrisisSocketEvent e, Emitter<CrisisState> emit) async {
    final d = e.data;
    switch (e.event) {
      case SocketEvents.crisisActivated:
        final info = CrisisInfo.fromJson(d);
        if (state.isActive && state.crisis?.id == info.id) return; // duplicate delivery
        emit(CrisisState(phase: CrisisPhase.active, crisis: info, activationSeq: state.activationSeq + 1));
        if (_isStaff()) await _refresh(emit);
      case SocketEvents.crisisUpdated:
        if (!state.isActive) return;
        final acc = d['accounted'];
        if (acc is Map) {
          emit(state.copyWith(roster: [for (final r in state.roster) r.userId == acc['workerId'].toString() ? r.withStatus(AccountedStatus.fromWire(acc['status'] as String)) : r]));
        } else {
          emit(state.copyWith(crisis: state.crisis?.copyWith(triggers: CrisisInfo.fromJson(d).triggers, zoneIds: CrisisInfo.fromJson(d).zoneIds)));
          if (_isStaff()) await _refresh(emit);
        }
      case SocketEvents.crisisPositions:
        if (!state.isActive) return;
        final list = ((d['positions'] as List?) ?? const []).map((p) => CrisisPosition.fromJson((p as Map).cast<String, dynamic>()));
        emit(state.copyWith(positions: {for (final p in list) p.userId: p}));
      case SocketEvents.crisisRoutes:
        if (!state.isActive) return;
        emit(state.copyWith(routes: CrisisRoute.parseCollection(d['geojson'])));
      case SocketEvents.crisisResolved:
        if (state.phase == CrisisPhase.idle) return;
        emit(state.copyWith(phase: CrisisPhase.resolved, falseAlarm: d['falseAlarm'] == true, resolvedAt: DateTime.tryParse('${d['resolvedAt']}')?.toUtc(), busy: false));
    }
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
