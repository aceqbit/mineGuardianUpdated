import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/contracts/enums.dart';
import 'package:mine_guardian/contracts/socket_events.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/session_bloc.dart';
import 'package:mine_guardian/core/models/mine_layout.dart';
import 'package:mine_guardian/core/models/sample_layout.dart';
import 'package:mine_guardian/core/models/session_user.dart';
import 'package:mine_guardian/core/sensors/local_frame.dart';
import 'package:mine_guardian/core/socket/socket_service.dart';
import 'package:mine_guardian/features/live_map/bloc/fleet_bloc.dart';
import 'package:mine_guardian/features/live_map/bloc/live_map_bloc.dart';
import 'package:mine_guardian/features/live_map/data/live_map_repository.dart';
import 'package:mine_guardian/features/live_map/data/route_modes.dart';
import 'package:mine_guardian/features/live_map/view/fleet_map_screen.dart';
import 'package:mine_guardian/features/live_map/view/live_map_screen.dart';
import 'package:mine_guardian/features/live_map/widgets/map_launch.dart';
import 'package:mine_guardian/features/profiles/data/profiles_repository.dart';

final mine = sampleLayout(); // the real seeded geometry (J0..J10 trunk at y=0, exits J0 / N5 / S2)
final frame = LocalFrame(mine.anchor.lat, mine.anchor.lng);
GeoPoint at(double x, double y) {
  final p = frame.toLatLng(x, y);
  return GeoPoint(p.lat, p.lng);
}

MapFix fix(double x, double y, {int sec = 0, double? speed}) {
  final p = at(x, y);
  return MapFix(lat: p.lat, lng: p.lng, accuracyM: 5, ts: DateTime.utc(2026, 10, 17, 4).add(Duration(seconds: sec)), source: PositionSource.fused, speedMps: speed);
}

class _FakeRepo implements LiveMapRepository {
  _FakeRepo({this.layoutData});
  MineLayoutData? layoutData;
  List<RouteHazard> hazardList = const [];
  List<FleetPosition> fleetList = const [];
  @override
  Future<MineLayoutData?> layout() async => layoutData;
  @override
  Future<List<RouteHazard>> hazards() async => hazardList;
  @override
  Future<List<FleetPosition>> fleet({String? zoneId}) async => fleetList;
  @override
  Future<Map<String, String>> zones() async => const {'zA': 'Z-A', 'zB': 'Z-B'};
}

Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  get currentUser => null;
}

class _NoServer implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString(jsonEncode({'profile': {'id': 'm2', 'fullName': 'Asha Devi', 'employeeId': 'MIN-0106', 'role': 'miner', 'level': 'full', 'zone': {'id': 'zB', 'code': 'Z-B', 'name': 'Central'}, 'today': {'status': 'PREDICTED', 'verdict': 'COMPLIANT'}}}), 200, headers: {Headers.contentTypeHeader: ['application/json']});
}

void main() {
  group('LiveMapBloc', () {
    test('defaults to the nearest exit, plans every mode and follows the miner', () async {
      final pos = StreamController<MapFix>();
      final bloc = LiveMapBloc(repo: _FakeRepo(layoutData: mine), positions: pos.stream)..add(const LiveMapStarted());
      pos.add(fix(-240, 2)); // near J1, next to Main Shaft (J0)
      await until(() => bloc.state.routes.isNotEmpty);
      expect(bloc.state.target!.id, 'X-MAIN');
      expect(bloc.state.startNode, 'J1');
      expect(bloc.state.routes.expand((r) => r.modes).toSet(), RouteMode.values.toSet());
      expect(bloc.state.selected!.modes, contains(RouteMode.leastHindrance));
      await bloc.close();
      await pos.close();
    });

    test('walking off the route by more than 15 m re-plans it; a new hazard closing the route re-plans too', () async {
      final pos = StreamController<MapFix>();
      final repo = _FakeRepo(layoutData: mine);
      final bloc = LiveMapBloc(repo: repo, positions: pos.stream, hazardEvery: const Duration(milliseconds: 100))..add(const LiveMapStarted());
      pos.add(fix(-60, 0)); // J4
      await until(() => bloc.state.routes.isNotEmpty);
      bloc.add(const LiveMapTargetChosen('X-INCL'));
      await until(() => bloc.state.target?.id == 'X-INCL' && bloc.state.routes.isNotEmpty);
      final before = bloc.state.replans;
      pos.add(fix(-60, 60, sec: 5)); // halfway up the cross-cut to N2, far from a trunk route
      await until(() => bloc.state.replans > before);
      final firstKey = bloc.state.selected!.key;
      // a CRITICAL hazard on the chosen way
      final mid = bloc.state.selected!.points;
      repo.hazardList = [RouteHazard(point: GeoPoint((mid[1].lat + mid[2].lat) / 2, (mid[1].lng + mid[2].lng) / 2), category: 'OTHER', severity: 'CRITICAL')];
      await until(() => bloc.state.selected?.key != firstKey);
      expect(bloc.state.planner!.closed, isNotEmpty);
      for (final r in bloc.state.routes) {
        expect(r.tunnelIds.toSet().intersection(bloc.state.planner!.closed), isEmpty);
      }
      await bloc.close();
      await pos.close();
    });

    test('outside the mine nothing is planned until a start is pinned; arrival is detected', () async {
      final pos = StreamController<MapFix>();
      final bloc = LiveMapBloc(repo: _FakeRepo(layoutData: mine), positions: pos.stream)..add(const LiveMapStarted());
      pos.add(fix(5000, 5000));
      await until(() => bloc.state.outsideMine);
      expect(bloc.state.routes, isEmpty);
      bloc.add(LiveMapStartPinned(at(180, 0))); // J8
      bloc.add(const LiveMapTargetChosen('RC-1'));
      await until(() => bloc.state.routes.isNotEmpty && bloc.state.target?.id == 'RC-1');
      expect(bloc.state.startNode, 'J8');
      bloc.add(const LiveMapStartPinned(null));
      pos.add(fix(120, 1, sec: 9)); // at J7 = the refuge
      await until(() => bloc.state.arrived);
      await bloc.close();
      await pos.close();
    });

    test('a long-press destination snaps to the nearest junction', () async {
      final pos = StreamController<MapFix>();
      final bloc = LiveMapBloc(repo: _FakeRepo(layoutData: mine), positions: pos.stream)..add(const LiveMapStarted());
      await until(() => bloc.state.status == LiveMapStatus.ready);
      bloc.add(LiveMapPointChosen(at(62, 115)));
      await until(() => bloc.state.target?.id == 'N3');
      await bloc.close();
      await pos.close();
    });

    test('no real layout -> noLayout (never the sample map)', () async {
      final bloc = LiveMapBloc(repo: _FakeRepo(), positions: const Stream.empty())..add(const LiveMapStarted());
      await until(() => bloc.state.status == LiveMapStatus.noLayout);
      await bloc.close();
    });
  });

  group('FleetBloc', () {
    FleetPosition p(String id, double x, int sec, {Presence presence = Presence.live, String zone = 'zB'}) {
      final g = at(x, 0);
      return FleetPosition(userId: id, name: id, employeeId: id.toUpperCase(), role: Role.miner, zoneId: zone, presence: presence, fix: MapFix(lat: g.lat, lng: g.lng, accuracyM: 5, ts: DateTime.utc(2026, 10, 17, 4).add(Duration(seconds: sec))));
    }

    test('merge keeps a 60 s trail, ignores out-of-order fixes', () {
      var m = FleetBloc.merge(const {}, [p('a', 0, 0)]);
      m = FleetBloc.merge(m, [p('a', 10, 10)]);
      m = FleetBloc.merge(m, [p('a', 5, 5)]); // older: ignored
      expect(m['a']!.now.fix.ts.second, 10);
      expect(m['a']!.trail.length, 2);
      m = FleetBloc.merge(m, [p('a', 20, 65)]);
      expect(m['a']!.trail.map((t) => t.$2.second), [10, 5], reason: 'the t=0 fix fell out of the 60 s window; t=10 and the new t=65 (05 s past the minute) remain');
    });

    test('live batches move people; SOS first, then live, stale, offline; zone filter', () async {
      final repo = _FakeRepo(layoutData: mine)..fleetList = [p('b', 0, 0, presence: Presence.offline), p('a', 60, 0)];
      final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x');
      final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = _NoServer());
      final bloc = FleetBloc(repo: repo, profiles: ProfilesRepository(api: api), socket: socket)..add(const FleetStarted());
      await until(() => bloc.state.people.length == 2);
      expect(bloc.state.visible.map((x) => x.now.userId), ['a', 'b']);
      final g = at(120, 0);
      socket.inject(SocketEvents.trackingPositions, {'positions': [{'userId': 'c', 'name': 'c', 'employeeId': 'C', 'role': 'miner', 'zoneId': 'zA', 'lat': g.lat, 'lng': g.lng, 'accuracyM': 4, 'presence': 'LIVE', 'sosId': 's1', 'ts': '2026-10-17T04:00:05Z'}]});
      await until(() => bloc.state.people.length == 3);
      expect(bloc.state.visible.first.now.userId, 'c');
      bloc.add(const FleetZoneChanged('zB'));
      await until(() => bloc.state.visible.length == 2);
      bloc.add(const FleetPersonSelected('a'));
      await until(() => bloc.state.selectedProfile != null);
      await bloc.close();
    });
  });

  testWidgets('launch mark plays once then gets out of the way', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: ThemeData(extensions: const [MgColors.light]), home: const MapLaunchOverlay(child: Text('map'))));
    expect(find.text('LIVE MAP'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(find.text('LIVE MAP'), findsNothing);
    expect(find.text('map'), findsOneWidget);
  });

  testWidgets('reduced motion skips the launch mark', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: ThemeData(extensions: const [MgColors.light]), home: const MediaQuery(data: MediaQueryData(disableAnimations: true), child: MapLaunchOverlay(child: Text('map')))));
    expect(find.text('LIVE MAP'), findsNothing);
  });

  Future<void> pump(WidgetTester tester, {required Size size, required bool dark, required SessionUser user, required Widget home}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = _NoServer());
    final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x');
    final session = SessionBloc(auth: _FakeAuth(), api: api)..add(LoggedIn(user));
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [RepositoryProvider<ApiClient>.value(value: api), RepositoryProvider<SocketService>.value(value: socket)],
      child: BlocProvider<SessionBloc>.value(
        value: session,
        child: MaterialApp(theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]), home: home),
      ),
    ));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const miner = SessionUser(id: 'm1', role: Role.miner, fullName: 'Ravi Kumar', employeeId: 'MIN-0105', phoneE164: '', zoneId: 'zB', zoneCode: 'Z-B', shift: Shift.a);
  const admin = SessionUser(id: 'x', role: Role.admin, fullName: 'Admin', employeeId: 'ADM-0001', phoneE164: '');

  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets('miner live map at ${size.width.toInt()}px dark=$dark: routes, turn-by-turn, no overflow', (tester) async {
        final pos = StreamController<MapFix>.broadcast();
        await pump(tester, size: size, dark: dark, user: miner, home: LiveMapScreen(repository: _FakeRepo(layoutData: mine), positions: pos.stream));
        pos.add(fix(-240, 2)); // next to J1: the nearest exit is the Main Shaft at J0
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.textContaining('to Main Shaft'), findsWidgets);
        expect(find.text('Least hindrance'), findsWidgets);
        expect(find.text('Destination'), findsOneWidget);
        await pos.close();
        await tester.pump(const Duration(milliseconds: 1200));
      });

      testWidgets('admin fleet map at ${size.width.toInt()}px dark=$dark: people listed and counted, no overflow', (tester) async {
        final g = at(0, 0);
        final repo = _FakeRepo(layoutData: mine)..fleetList = [
          FleetPosition(userId: 'm2', name: 'Asha Devi', employeeId: 'MIN-0106', role: Role.miner, zoneId: 'zB', presence: Presence.live, fix: MapFix(lat: g.lat, lng: g.lng, accuracyM: 6, ts: DateTime.now().toUtc(), source: PositionSource.pdr, tunnelId: 'T-J4-J5', headingDeg: 90)),
          FleetPosition(userId: 'm3', name: 'Mohan Singh', employeeId: 'MIN-0107', role: Role.miner, zoneId: 'zB', presence: Presence.offline, fix: MapFix(lat: g.lat, lng: g.lng + 0.001, accuracyM: 9, ts: DateTime.now().toUtc().subtract(const Duration(minutes: 5)))),
        ];
        await pump(tester, size: size, dark: dark, user: admin, home: FleetMapScreen(repository: repo));
        expect(find.text('1 live'), findsOneWidget);
        expect(find.text('1 offline'), findsOneWidget);
        expect(find.text('Asha Devi'), findsOneWidget);
        expect(find.text('Whole mine'), findsOneWidget);
        await tester.tap(find.text('Asha Devi'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Open profile'), findsOneWidget);
        expect(find.text('Compliant'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1200));
      });
    }
  }
}
