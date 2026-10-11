import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/db/layout_repository.dart';
import '../../../core/location/location_service.dart';
import '../../../core/models/mine_layout.dart';
import '../../../core/models/sample_layout.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/sync/outbox_queue.dart';
import '../../../core/sync/sync_engine.dart';
import '../data/evac_graph.dart';
import '../data/nav_logic.dart';
import '../data/sos_repository.dart';
import 'sos_event.dart';
import 'sos_state.dart';

/// SOS and evacuation: sends the alert (outbox when offline), streams GPS every 10 s, keeps an on-device evacuation route
/// and shows the control room's route when one arrives.
class SosBloc extends Bloc<SosEvent, SosState> {
  SosBloc({
    required SosRepository repo,
    required LocationService location,
    required SocketService socket,
    required SyncEngine engine,
    required OutboxQueue queue,
    required LayoutRepository layout,
    required this.userId,
    required this.zoneCode,
    this.designatedExitId,
  })  : _repo = repo,
        _location = location,
        _socket = socket,
        _engine = engine,
        _queue = queue,
        _layoutRepo = layout,
        super(const SosState()) {
    on<SosOpened>(_onOpened);
    on<SosLocationChanged>(_onLocation);
    on<SosQueuedResult>((e, emit) => emit(state.copyWith(status: SosSendStatus.sent, sentAt: DateTime.now(), sosId: e.sosId)));
    on<SosRoutesReceived>(_onRoutes);
    on<SosRouteAssigned>((e, emit) => emit(state.copyWith(assignedRank: e.rank)));
    on<SosGpsTick>(_onGpsTick);
    on<SosCancelConfirmed>(_onCancel);
    on<SosRouteSelected>((e, emit) {
      emit(state.copyWith(workerPickedExitId: e.exitId));
      _rebuildGraph(emit);
    });
    on<SosStartPinned>((e, emit) {
      emit(state.copyWith(pinnedStart: e.point, clearPinnedStart: e.point == null, clearPicked: true));
      _rebuildGraph(emit);
    });
    on<SosDestinationSelected>((e, emit) {
      emit(state.copyWith(destinationId: e.id, clearDestination: e.id == null, clearPicked: true));
      _rebuildGraph(emit);
    });
    on<SosSimulateToggled>(_onSimulate);
    on<SosRefreshTick>(_onRefresh);
    on<SosRetrySend>((e, emit) => _send(emit));
    on<SosLayoutLoaded>((e, emit) {
      emit(state.copyWith(layout: e.layout));
      _rebuildGraph(emit);
    });
  }

  final SosRepository _repo;
  final LocationService _location;
  final SocketService _socket;
  final SyncEngine _engine;
  final OutboxQueue _queue;
  final LayoutRepository _layoutRepo;
  final String userId;
  final String zoneCode;

  /// Layout exit id the admin designated for this worker's zone (null = nearest safe exit).
  final String? designatedExitId;

  final String clientId = SosRepository.newClientId();
  final DateTime triggeredAt = DateTime.now().toUtc();
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _gps;
  Timer? _refresh;
  StreamSubscription<LocationFix>? _sim;
  GeoPoint? _lastRouted;
  EvacGraph? _graph;

  Future<void> _onOpened(SosOpened e, Emitter<SosState> emit) async {
    emit(state.withEvacOnly(e.evacOnly));

    // Offline-first data: cached layout + cached hazards.
    final layout = await _layoutRepo.cached();
    final hazards = (await _layoutRepo.cachedOpenHazards()).map(CachedHazard.fromJson).whereType<CachedHazard>().toList();
    emit(state.copyWith(layout: layout ?? sampleLayout(), hazards: hazards, zoneCode: zoneCode));
    _rebuildGraph(emit);
    _layoutRepo.refresh().then((fresh) {
      if (fresh != null && fresh.version != state.layout?.version && !isClosed) add(SosLayoutLoaded(fresh));
    });

    // Live control-room routes.
    _subs.add(_socket.on(SocketEvents.crisisRoutes).listen((env) => add(SosRoutesReceived(env.data))));
    _subs.add(_socket.on(SocketEvents.crisisRouteAssigned).listen((env) {
      if ((env.data['workerId'] ?? '').toString() == userId) add(SosRouteAssigned((env.data['rank'] as num?)?.toInt() ?? 1));
    }));

    // Location: last known first, then refined.
    final last = await _location.lastKnown();
    if (last != null) add(SosLocationChanged(last));
    _subs.add(_location.stream().listen((f) => add(SosLocationChanged(f)), onError: (_) {}));
    _location.getCurrent().then((f) {
      if (f != null && !isClosed) add(SosLocationChanged(f));
    });

    // Pick up newly cached hazards and layout changes (blocked tunnels) while the screen is open.
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!isClosed) add(const SosRefreshTick());
    });

    if (!e.evacOnly) {
      await _send(emit);
      _gps = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!isClosed) add(const SosGpsTick());
      });
    }
  }

  void _onLocation(SosLocationChanged e, Emitter<SosState> emit) {
    if (_sim != null && !e.simulated) return; // real GPS is paused while the simulator walks
    emit(state.copyWith(fix: e.fix, positionUnknown: false));
    // Reroute on the first fix and whenever the worker has moved more than 10 m since the last computation.
    final last = _lastRouted;
    if (state.pinnedStart == null && (last == null || state.layout == null || haversineM(last, GeoPoint(e.fix.lat, e.fix.lng)) > 10)) _rebuildGraph(emit);
  }

  /// Offline route from the cached layout, recomputed whenever position / layout / hazards change.
  void _rebuildGraph(Emitter<SosState> emit) {
    final layout = state.layout;
    if (layout == null) return;
    _graph = EvacGraph.build(layout, hazards: state.hazards);
    final fix = state.fix;
    final here = state.pinnedStart ?? (fix != null && !state.fixOutsideMine ? GeoPoint(fix.lat, fix.lng) : _zoneCentre(layout));
    final choice = chooseTarget(graph: _graph!, from: here, designatedExitId: designatedExitId, workerPickedExitId: state.workerPickedExitId, destinationId: state.destinationId);
    final picked = choice.route;
    _lastRouted = here;
    emit(state.copyWith(alternatives: choice.alternatives, offlineRoute: picked, clearOfflineRoute: picked == null, selectedExitId: picked?.exit.id, selectedRouteKey: picked?.key, targetReason: choice.reason, positionUnknown: (fix == null || state.fixOutsideMine) && state.pinnedStart == null));
  }

  GeoPoint? _zoneCentre(MineLayoutData layout) {
    final zone = layout.zones.where((z) => z.code == zoneCode).firstOrNull;
    if (zone == null || zone.ring.isEmpty) return null;
    final ring = zone.ring;
    return GeoPoint(ring.map((p) => p.lat).reduce((a, b) => a + b) / ring.length, ring.map((p) => p.lng).reduce((a, b) => a + b) / ring.length);
  }

  Future<void> _onSimulate(SosSimulateToggled e, Emitter<SosState> emit) async {
    if (!state.evacOnly) return; // never feed made-up positions into a real SOS
    if (_sim != null) {
      await _sim!.cancel();
      _sim = null;
      emit(state.copyWith(simulating: false));
      return;
    }
    final route = state.offlineRoute;
    if (route == null) return;
    emit(state.copyWith(simulating: true));
    _sim = simulateWalk(route).listen(
      (f) => add(SosLocationChanged(f, simulated: true)),
      onDone: () {
        if (!isClosed) add(const SosSimulateToggled()); // walk finished: toggles off (the subscription is still set)
      },
    );
  }

  Future<void> _onRefresh(SosRefreshTick e, Emitter<SosState> emit) async {
    try {
    final hz = (await _layoutRepo.cachedOpenHazards()).map(CachedHazard.fromJson).whereType<CachedHazard>().toList();
    if (hz.length != state.hazards.length) emit(state.copyWith(hazards: hz));
    final fresh = await _layoutRepo.refresh();
    if (fresh != null && fresh.version != state.layout?.version) emit(state.copyWith(layout: fresh));
    } catch (_) {// offline: keep what we have
    }
    _rebuildGraph(emit);
  }

  Future<void> _send(Emitter<SosState> emit) async {
    emit(state.copyWith(status: SosSendStatus.sending));
    final fix = state.fix ?? await _location.lastKnown();
    try {
      final res = await _repo.send(clientId: clientId, fix: fix, triggeredAt: triggeredAt);
      emit(state.copyWith(status: SosSendStatus.sent, sentAt: DateTime.now(), sosId: res.sosId));
    } on ApiException catch (ex) {
      final retryable = ex.isNetwork || (ex.statusCode ?? 500) >= 500;
      if (!retryable) {
        emit(state.copyWith(status: SosSendStatus.failed));
        return;
      }
      await _queue.enqueueSos(clientId: clientId, payload: SosRepository.payload(fix, triggeredAt));
      emit(state.copyWith(status: SosSendStatus.savedOffline, retries: state.retries + 1));
      _subs.add(_engine.itemResult$.where((x) => x.id == clientId).listen((x) {
        if (x.success) {
          final s = (x.response?['sos'] as Map?)?.cast<String, dynamic>();
          add(SosQueuedResult((s?['id'] ?? s?['_id'])?.toString()));
        }
      }));
    } catch (_) {
      emit(state.copyWith(status: SosSendStatus.failed));
    }
  }

  Future<void> _onGpsTick(SosGpsTick e, Emitter<SosState> emit) async {
    if (state.cancelled) return;
    _rebuildGraph(emit);
    if (state.evacOnly) return;
    final fix = state.fix;
    if (fix == null) return;
    final data = {'lat': fix.lat, 'lng': fix.lng, 'accuracyM': fix.accuracyM, 'ts': DateTime.now().toUtc().toIso8601String(), if (state.sosId != null) 'sosId': state.sosId};
    if (_socket.isConnected) {
      await _socket.emit(SocketEvents.gpsUpdate, data);
    } else {
      await _queue.enqueueGps(clientId: SosRepository.newClientId(), payload: data);
    }
    if (state.status == SosSendStatus.savedOffline) emit(state.copyWith(retries: state.retries + 1));
  }

  void _onRoutes(SosRoutesReceived e, Emitter<SosState> emit) {
    final feats = (e.collection['geojson'] is Map ? (e.collection['geojson'] as Map)['features'] : e.collection['features']) as List? ?? const [];
    final mine = <ControlRoute>[];
    for (final f in feats) {
      final props = ((f as Map)['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
      if ((props['workerId'] ?? '').toString() != userId) continue;
      final coords = ((f['geometry'] as Map)['coordinates'] as List).map((c) => GeoPoint.fromCoord(c as List)).toList();
      mine.add(ControlRoute(
        rank: (props['rank'] as num?)?.toInt() ?? 1,
        points: coords,
        exitName: props['exitName'] as String? ?? 'exit',
        etaSec: (props['etaSec'] as num?)?.toDouble() ?? 0,
        recommended: props['recommended'] == true || (props['rank'] as num?)?.toInt() == 1,
      ));
    }
    mine.sort((a, b) => a.rank.compareTo(b.rank));
    emit(state.copyWith(controlRoutes: mine));
  }

  Future<void> _onCancel(SosCancelConfirmed e, Emitter<SosState> emit) async {
    _gps?.cancel();
    final key = state.sosId ?? clientId;
    try {
      await _repo.cancel(key);
    } on ApiException catch (ex) {
      if (ex.isNetwork || (ex.statusCode ?? 500) >= 500) {
        await _queue.enqueueSosCancel(clientId: SosRepository.newClientId(), sosKey: key);
      }
    } catch (_) {
      await _queue.enqueueSosCancel(clientId: SosRepository.newClientId(), sosKey: key);
    }
    emit(state.copyWith(cancelled: true));
  }

  @override
  Future<void> close() async {
    _gps?.cancel();
    _refresh?.cancel();
    await _sim?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
