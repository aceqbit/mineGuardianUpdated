import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/contracts/enums.dart';
import 'package:mine_guardian/contracts/routes.dart';
import 'package:mine_guardian/contracts/socket_events.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/session_bloc.dart';
import 'package:mine_guardian/core/models/session_user.dart';
import 'package:mine_guardian/core/socket/socket_service.dart';
import 'package:mine_guardian/features/finish/widgets/feature_dock.dart';

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  get currentUser => null;
}

class _Server implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final crisis = o.path == '/api/crisis/active';
    return ResponseBody.fromString(jsonEncode(crisis ? {'active': false} : {'error': {'code': 'NOT_FOUND', 'message': 'nf'}}), crisis ? 200 : 404, headers: {Headers.contentTypeHeader: ['application/json']});
  }
}

const miner = SessionUser(id: 'm1', role: Role.miner, fullName: 'Ravi Kumar', employeeId: 'MIN-0105', phoneE164: '', zoneId: 'zB', zoneCode: 'Z-B', shift: Shift.a, zoneSupervisors: [ZoneSupervisor(name: 'Sunil Banerjee', e164: '+919876500012', id: 's1')]);
const supervisor = SessionUser(id: 's1', role: Role.supervisor, fullName: 'Sunil Banerjee', employeeId: 'SUP-0012', phoneE164: '', zoneId: 'zB');
const admin = SessionUser(id: 'a1', role: Role.admin, fullName: 'Admin One', employeeId: 'ADM-0001', phoneE164: '');

void main() {
  test('the dock stays off sign-in, SOS / evacuation and the crisis consoles', () {
    for (final p in [Routes.login, Routes.signup, Routes.splash, Routes.workerSos, Routes.adminCrisis, Routes.crisisView, '/dev/ui']) {
      expect(dockVisibleFor(p), isFalse, reason: p);
    }
    for (final p in [Routes.worker, Routes.supervisor, Routes.admin, Routes.leaderboard, Routes.workerMap, Routes.adminProfiles, '/profiles/abc']) {
      expect(dockVisibleFor(p), isTrue, reason: p);
    }
  });

  test('shortcuts per role are the add-ons that role can open', () {
    expect(dockShortcuts(miner).map((s) => s.label), ['Profiles', 'Live map', 'Safety today', 'AI call Sunil']);
    expect(dockShortcuts(supervisor).map((s) => s.route), [Routes.supervisorProfiles, Routes.supervisorLiveMap]);
    expect(dockShortcuts(admin).map((s) => s.route), [Routes.adminProfiles, Routes.adminLiveMap, Routes.adminContacts]);
    expect(dockShortcuts(const SessionUser(id: 'm', role: Role.miner, fullName: 'X', employeeId: 'X', phoneE164: '')).length, 3, reason: 'no AI-call shortcut without a known supervisor');
  });

  Future<SocketService> pump(WidgetTester tester, {required Size size, required bool dark, required SessionUser user, String location = Routes.worker}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = _Server());
    final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x');
    final session = SessionBloc(auth: _FakeAuth(), api: api)..add(LoggedIn(user));
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [RepositoryProvider<ApiClient>.value(value: api), RepositoryProvider<SocketService>.value(value: socket)],
      child: BlocProvider<SessionBloc>.value(
        value: session,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]),
          home: FeatureDockFrame(location: location, child: Scaffold(appBar: AppBar(title: const Text('Page')), body: const Center(child: Text('content')))),
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return socket;
  }

  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      for (final u in [miner, supervisor, admin]) {
        testWidgets('dock for ${u.role.name} at ${size.width.toInt()}px dark=$dark: shortcuts + status, no overflow', (tester) async {
          await pump(tester, size: size, dark: dark, user: u);
          expect(find.text('content'), findsOneWidget, reason: 'the page is still there');
          if (size.width < 600) {
            expect(find.byTooltip('Profiles'), findsOneWidget);
            expect(find.byTooltip('Live map'), findsOneWidget);
          } else {
            expect(find.text('Profiles'), findsOneWidget);
            expect(find.text('No crisis'), findsOneWidget);
            expect(find.text('Offline'), findsOneWidget);
          }
        });
      }
    }
  }

  testWidgets('a crisis shows on the dock live', (tester) async {
    final socket = await pump(tester, size: const Size(1280, 800), dark: false, user: admin, location: Routes.admin);
    expect(find.text('No crisis'), findsOneWidget);
    socket.inject(SocketEvents.crisisActivated, {'crisisId': 'c1'}, id: 'ca1');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Crisis active'), findsOneWidget);
    socket.inject(SocketEvents.crisisResolved, {'crisisId': 'c1'}, id: 'cr1');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No crisis'), findsOneWidget);
  });

  testWidgets('no dock on the SOS screen', (tester) async {
    await pump(tester, size: const Size(360, 780), dark: false, user: miner, location: Routes.workerSos);
    expect(find.byTooltip('Profiles'), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });
}
