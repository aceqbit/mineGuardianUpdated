import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_nav.dart';
import 'admin_home_event.dart';
import 'admin_home_state.dart';

/// Overview over REST, refreshed (debounced 1 s) on live events. `sla:breach` shows a toast and a badge count.
class AdminHomeBloc extends Bloc<AdminHomeEvent, AdminHomeState> {
  AdminHomeBloc({required AdminRepository repo, required SocketService socket, this.debounce = const Duration(seconds: 1)}) : _repo = repo, super(const AdminHomeState()) {
    on<AdminHomeStarted>((e, emit) async {
      emit(state.copyWith(status: AdminStatus.loading));
      await _load(emit);
    });
    on<AdminHomeRefreshRequested>((e, emit) => _load(emit));
    on<AdminSocketEvent>(_onSocket);
    on<SupervisorsAssigned>(_onAssign);
    on<ZoneExitChosen>(_onExit);
    on<AdminNoticeShown>((e, emit) => emit(state.copyWith(clearNotice: true)));

    for (final ev in [SocketEvents.checkinNew, SocketEvents.complianceReviewed, SocketEvents.hazardNew, SocketEvents.hazardUpdated, SocketEvents.sosTriggered, SocketEvents.crisisActivated, SocketEvents.crisisResolved, SocketEvents.slaBreach]) {
      _subs.add(socket.on(ev).listen((env) => add(AdminSocketEvent(ev, env.data))));
    }
  }

  final AdminRepository _repo;
  final Duration debounce;
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _timer;

  Future<void> _load(Emitter<AdminHomeState> emit) async {
    try {
      final ov = await _repo.overview();
      final sups = state.supervisors.isEmpty ? await _repo.supervisors() : state.supervisors;
      List<ExitRef>? exits;
      if (state.exits.isEmpty) {
        try {
          exits = await _repo.exits();
        } catch (_) {// the picker just stays empty; the overview still loads
        }
      }
      emit(state.copyWith(status: AdminStatus.ready, overview: ov, supervisors: sups, exits: exits));
    } on ApiException catch (e) {
      emit(state.copyWith(status: state.overview == null ? AdminStatus.failure : AdminStatus.ready, notice: e.message, noticeIsError: true));
    }
  }

  void _onSocket(AdminSocketEvent e, Emitter<AdminHomeState> emit) {
    if (e.event == SocketEvents.slaBreach) {
      final n = state.slaBreaches + 1;
      AdminBadges.sla.value = n;
      emit(state.copyWith(slaBreaches: n, notice: 'SLA breach: ${e.data['supervisorName'] ?? 'a supervisor'} has not decided a review in time'));
    }
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (!isClosed) add(const AdminHomeRefreshRequested());
    });
  }

  Future<void> _onAssign(SupervisorsAssigned e, Emitter<AdminHomeState> emit) async {
    try {
      await _repo.setZoneSupervisors(e.zoneId, e.supervisorIds);
      final sups = await _repo.supervisors();
      emit(state.copyWith(supervisors: sups, notice: 'Supervisors updated'));
      await _load(emit);
    } on ApiException catch (ex) {
      emit(state.copyWith(notice: ex.message, noticeIsError: true));
    }
  }

  Future<void> _onExit(ZoneExitChosen e, Emitter<AdminHomeState> emit) async {
    try {
      await _repo.setZoneEvacExit(e.zoneId, e.exitId);
      emit(state.copyWith(notice: e.exitId == null ? 'Emergency exit: nearest safe exit' : 'Emergency exit saved'));
      await _load(emit);
    } on ApiException catch (ex) {
      emit(state.copyWith(notice: ex.message, noticeIsError: true));
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
