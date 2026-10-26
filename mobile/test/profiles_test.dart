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
import 'package:mine_guardian/core/models/session_user.dart';
import 'package:mine_guardian/core/socket/socket_service.dart';
import 'package:mine_guardian/features/profiles/bloc/profiles_bloc.dart';
import 'package:mine_guardian/features/profiles/data/profile_models.dart';
import 'package:mine_guardian/features/profiles/data/profiles_repository.dart';
import 'package:mine_guardian/features/profiles/view/profile_detail_screen.dart';
import 'package:mine_guardian/features/profiles/view/profiles_screen.dart';
import 'package:mine_guardian/features/profiles/widgets/profile_editor_sheet.dart';

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  get currentUser => null;
}

Map<String, dynamic> card(String id, String name, {String role = 'miner', String level = 'full', String? band, int? score = 640, String today = 'PREDICTED', String? verdict = 'COMPLIANT', String? presence = 'LIVE'}) => {
      'id': id, 'fullName': name, 'employeeId': 'MIN-$id', 'role': role, 'status': 'active', 'shift': 'A', 'level': level,
      'zone': {'id': 'zB', 'code': 'Z-B', 'name': 'Central Panel'}, 'designation': 'Roof bolter',
      'today': role == 'miner' ? {'status': today, 'verdict': verdict} : null,
      if (level != 'crew') 'score': {'score': score, 'streak': 4, 'xp': 120, 'badges': 2, 'rank': 2},
      if (level == 'crew') 'score': {'streak': 4, 'xp': 120, 'rank': 2},
      'riskBand': ?band,
      'presence': ?presence,
    };

Map<String, dynamic> detail(String id, String name, {String level = 'full', String designation = 'Roof bolter'}) => {
      ...card(id, name, level: level),
      'designation': designation,
      'email': 'r***@x.com', 'phoneMasked': '+91******0101', 'hasPhone': true, 'joinedAt': '2024-02-01T00:00:00Z',
      'experienceYears': 6, 'bloodGroup': 'O+', 'medicalNotes': 'Asthma inhaler in locker',
      'certifications': [{'name': 'Gas testing', 'expiresAt': '2026-11-01T00:00:00Z'}],
      'certificationsExpiring': [{'name': 'Gas testing', 'expiresAt': '2026-11-01T00:00:00Z', 'expired': false}],
      'requiredPpe': ['HELMET', 'REFLECTIVE_VEST', 'SAFETY_BOOTS', 'GLOVES'],
      'calendar': [for (var i = 0; i < 30; i++) {'day': '2026-09-${(i % 28 + 1).toString().padLeft(2, '0')}', 'verdict': i % 7 == 0 ? 'NON_COMPLIANT' : (i % 3 == 0 ? null : 'COMPLIANT')}],
      'score': {'score': 640, 'streak': 4, 'xp': 120, 'badges': [{'key': 'STREAK_7'}], 'riskBand': level == 'full' ? 'AMBER' : null, 'rank': 2, 'rankOf': 8, 'history': [{'day': '2026-10-15', 'score': 610}, {'day': '2026-10-16', 'score': 640}]},
      'rewards': [{'title': 'Safety Star'}],
      'hazards': {'counts': {'OPEN': 1, 'CLOSED': 3}, 'recent': [{'id': 'h1', 'category': 'ROOF_FALL', 'status': 'OPEN', 'createdAt': '2026-10-16T08:00:00Z'}]},
      'sos': {'count': 0, 'recent': []},
      'presence': {'presence': 'LIVE', 'lat': 23.7, 'lng': 86.4, 'accuracyM': 6, 'source': 'FUSED', 'tunnelId': 'T-J4-J5', 'ts': '2026-10-17T05:00:00Z'},
    };

/// Serves /api/profiles and /api/profiles/:id and counts the detail requests.
class _Server implements HttpClientAdapter {
  _Server(this.items);
  final List<Map<String, dynamic>> items;
  final detailHits = <String, int>{};
  String designation = 'Roof bolter';
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    ResponseBody json(Object b, [int code = 200]) => ResponseBody.fromString(jsonEncode(b), code, headers: {Headers.contentTypeHeader: ['application/json']});
    if (o.path == '/api/profiles') return json({'items': items, 'total': items.length, 'nextCursor': null});
    final m = RegExp(r'^/api/profiles/(\w+)$').firstMatch(o.path);
    if (m != null) {
      final id = m.group(1)!;
      detailHits[id] = (detailHits[id] ?? 0) + 1;
      final it = items.firstWhere((x) => x['id'] == id, orElse: () => const {});
      if (it.isEmpty) return json({'error': {'code': 'FORBIDDEN_SCOPE', 'message': 'out of scope'}}, 403);
      return json({'profile': detail(id, it['fullName'] as String, level: it['level'] as String, designation: designation)});
    }
    return json({'error': {'code': 'NOT_FOUND', 'message': 'nf'}}, 404);
  }
}

/// Waits for real timers (debounces) without a fixed sleep: fails after [timeout].
Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('profile patch builder (no pre-filled values: empty = unchanged)', () {
    test('only typed fields are sent; cleared fields go as null', () {
      final r = buildProfilePatch(admin: true, designation: '  Shot firer ', phone: '+91 98765 00101', cleared: {'medicalNotes'});
      expect(r.error, isNull);
      expect(r.body, {'designation': 'Shot firer', 'phoneE164': '+919876500101', 'medicalNotes': null});
    });
    test('miners can only send their designation', () {
      final r = buildProfilePatch(admin: false, designation: 'Helper', phone: '+919876500101', bloodGroup: 'O+', cleared: {'medicalNotes'});
      expect(r.body, {'designation': 'Helper'});
      expect(buildProfilePatch(admin: false, cleared: {'designation', 'bloodGroup'}).body, {'designation': null});
    });
    test('invalid phone and experience are rejected before the request', () {
      expect(buildProfilePatch(admin: true, phone: '98765').error, contains('international'));
      expect(buildProfilePatch(admin: true, experienceYears: '99').error, contains('Experience'));
      expect(buildProfilePatch(admin: true).body, isEmpty);
    });
    test('certifications serialise with ISO dates', () {
      final r = buildProfilePatch(admin: true, certifications: [Certification(name: 'First aid', expiresAt: DateTime.utc(2027, 1, 1))]);
      expect(r.body['certifications'], [{'name': 'First aid', 'expiresAt': '2027-01-01T00:00:00.000Z'}]);
    });
  });

  group('models', () {
    test('crew card has no score or risk band; full card has both', () {
      final crew = ProfileCard.fromJson(card('a', 'Ravi', level: 'crew', band: null));
      expect(crew.level, ProfileLevel.crew);
      expect(crew.score, isNull);
      expect(crew.streak, 4);
      final full = ProfileCard.fromJson(card('b', 'Asha', band: 'RED'));
      expect(full.riskBand, RiskBand.red);
      expect(full.presence, Presence.live);
      expect(full.today!.verdict, Verdict.compliant);
    });
    test('detail parses every section and maps back to a card', () {
      final d = ProfileDetail.fromJson(detail('b', 'Asha'));
      expect(d.calendar.length, 30);
      expect(d.score!.history.length, 2);
      expect(d.expiring.single.name, 'Gas testing');
      expect(d.presence!.source, PositionSource.fused);
      expect(d.requiredPpe.length, 4);
      final c = ProfileCard.fromDetail(d);
      expect(c.score, 640);
      expect(c.riskBand, RiskBand.amber);
    });
  });

  group('ProfilesBloc live updates', () {
    test('profile:updated refetches only that card, once per burst, and pulses it', () async {
      final server = _Server([card('a', 'Ravi'), card('b', 'Asha'), card('c', 'Mohan')]);
      final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = server);
      final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x');
      final bloc = ProfilesBloc(repo: ProfilesRepository(api: api), socket: socket, viewerId: 's1', viewerRole: Role.supervisor)..add(const ProfilesStarted());
      await until(() => bloc.state.items.length == 3);
      server.designation = 'Shot firer';
      for (var i = 0; i < 3; i++) {
        socket.inject(SocketEvents.profileUpdated, {'userId': 'b', 'changed': ['identity']});
      }
      await until(() => bloc.state.pulse.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300)); // a second refetch would land here
      expect(server.detailHits, {'b': 1});
      expect(bloc.state.items.firstWhere((x) => x.id == 'b').designation, 'Shot firer');
      expect(bloc.state.items.firstWhere((x) => x.id == 'a').designation, 'Roof bolter');
      expect(bloc.state.pulse, {'b': 1});
      socket.inject(SocketEvents.trackingPositions, {'positions': [{'userId': 'a', 'presence': 'STALE'}]});
      await until(() => bloc.state.items.firstWhere((x) => x.id == 'a').presence == Presence.stale);
      await bloc.close();
    });

    test('a profile that moved out of scope (403) disappears', () async {
      final server = _Server([card('a', 'Ravi'), card('b', 'Asha')]);
      final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = server);
      final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x');
      final bloc = ProfilesBloc(repo: ProfilesRepository(api: api), socket: socket, viewerId: 's1', viewerRole: Role.supervisor)..add(const ProfilesStarted());
      await until(() => bloc.state.items.length == 2);
      server.items.removeWhere((x) => x['id'] == 'b');
      socket.inject(SocketEvents.profileUpdated, {'userId': 'b', 'changed': ['identity']});
      await until(() => bloc.state.items.length == 1);
      expect(bloc.state.items.map((x) => x.id), ['a']);
      expect(bloc.state.total, 1);
      await bloc.close();
    });
  });

  final viewers = {
    Role.miner: (const SessionUser(id: 'a', role: Role.miner, fullName: 'Ravi Kumar', employeeId: 'MIN-0105', phoneE164: '', zoneId: 'zB', zoneCode: 'Z-B', shift: Shift.a), [card('a', 'Ravi Kumar', level: 'self'), card('b', 'Asha Devi', level: 'crew'), card('s', 'Sunil Banerjee', role: 'supervisor', level: 'crew', presence: null)]),
    Role.supervisor: (const SessionUser(id: 's', role: Role.supervisor, fullName: 'Sunil Banerjee', employeeId: 'SUP-0012', phoneE164: '', zoneId: 'zB', zoneCode: 'Z-B', shift: Shift.a), [card('a', 'Ravi Kumar', band: 'GREEN'), card('b', 'Asha Devi', band: 'RED', today: 'NOT_CHECKED_IN', verdict: null), card('s', 'Sunil Banerjee', role: 'supervisor')]),
    Role.admin: (const SessionUser(id: 'x', role: Role.admin, fullName: 'Admin One', employeeId: 'ADM-0001', phoneE164: ''), [card('a', 'Ravi Kumar', band: 'AMBER'), card('s', 'Sunil Banerjee', role: 'supervisor'), card('x', 'Admin One', role: 'admin', presence: null, score: null)]),
  };

  Future<void> pumpWith(WidgetTester tester, {required Size size, required bool dark, required SessionUser user, required _Server server, required Widget home}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = server);
    final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x');
    final session = SessionBloc(auth: _FakeAuth(), api: api)..add(LoggedIn(user));
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [RepositoryProvider<ApiClient>.value(value: api), RepositoryProvider<SocketService>.value(value: socket)],
      child: BlocProvider<SessionBloc>.value(
        value: session,
        child: MaterialApp(theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]), home: home),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 900));
  }

  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      for (final v in viewers.entries) {
        testWidgets('profiles screen ${v.key.name} at ${size.width.toInt()}px dark=$dark: cards render, no overflow', (tester) async {
          final server = _Server(v.value.$2);
          await pumpWith(tester, size: size, dark: dark, user: v.value.$1, server: server, home: const ProfilesScreen());
          expect(find.text('Asha Devi').evaluate().isNotEmpty || v.key == Role.admin, isTrue);
          expect(find.text('Sunil Banerjee'), findsOneWidget);
          if (v.key == Role.miner) {
            expect(find.text('Your crew'), findsOneWidget);
            expect(find.text('Red'), findsNothing);
          }
          if (v.key == Role.supervisor) expect(find.text('Red · 1'), findsOneWidget);
          if (v.key == Role.admin) expect(find.text('Supervisors'), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 600));
        });
      }

      testWidgets('profile detail at ${size.width.toInt()}px dark=$dark: every section, no overflow', (tester) async {
        final server = _Server([card('b', 'Asha Devi')]);
        await pumpWith(tester, size: size, dark: dark, user: viewers[Role.supervisor]!.$1, server: server, home: const ProfileDetailScreen(userId: 'b'));
        for (final title in ['Identity', 'Live location', 'Compliance', 'Safety score']) {
          await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
          expect(find.text(title), findsOneWidget);
        }
        await tester.scrollUntilVisible(find.text('Health & certifications'), 300, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('Gas testing'), findsOneWidget);
        expect(find.text('Edit'), findsNothing, reason: 'supervisors cannot edit');
        await tester.pump(const Duration(milliseconds: 600));
      });
    }
  }

  testWidgets('crew detail hides private sections and shows the crew note', (tester) async {
    final server = _Server([card('b', 'Asha Devi', level: 'crew')]);
    await pumpWith(tester, size: const Size(768, 1024), dark: false, user: viewers[Role.miner]!.$1, server: server, home: const ProfileDetailScreen(userId: 'b'));
    expect(find.textContaining('Crew view'), findsOneWidget);
    expect(find.text('Health & certifications'), findsNothing);
    expect(find.text('Compliance'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('admin sees Edit and the editor starts empty', (tester) async {
    final server = _Server([card('b', 'Asha Devi')]);
    await pumpWith(tester, size: const Size(768, 1024), dark: false, user: viewers[Role.admin]!.$1, server: server, home: const ProfileDetailScreen(userId: 'b'));
    // The FAB appears once the profile has loaded; let its entrance animation finish before tapping.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Edit'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Edit Asha Devi'), findsOneWidget);
    expect(find.text('Current: Roof bolter'), findsOneWidget);
    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(fields.every((f) => f.controller.text.isEmpty), isTrue, reason: 'no pre-filled values');
  });
}
