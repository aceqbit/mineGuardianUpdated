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
import 'package:mine_guardian/core/db/cache_repository.dart';
import 'package:mine_guardian/core/db/memory_outbox.dart';
import 'package:mine_guardian/core/socket/socket_service.dart';
import 'package:mine_guardian/features/safety_feed/bloc/safety_feed_bloc.dart';
import 'package:mine_guardian/features/safety_feed/data/safety_feed_repository.dart';
import 'package:mine_guardian/features/safety_feed/view/safety_screen.dart';
import 'package:mine_guardian/features/safety_feed/widgets/safety_bar.dart';

Map<String, dynamic> feedJson({int version = 1}) => {
      'date': '2026-10-17',
      'version': version,
      'generatedAt': '2026-10-17T00:30:00Z',
      'items': [
        {'id': 'r1', 'kind': 'RULE', 'title': 'Check your self-rescuer seal', 'body': 'A broken seal means the unit may not work. Report it before you go underground.', 'steps': [], 'sources': [{'domain': 'dgms.gov.in', 'title': 'dgms.gov.in'}]},
        {'id': 'g1', 'kind': 'REACT', 'title': 'If you smell gas', 'body': 'Stop work, warn others and walk to fresh intake air at once.', 'steps': ['Put on the self-rescuer', 'Walk to intake air', 'Tell your supervisor'], 'hazardCategory': 'GAS_LEAK', 'sources': [{'domain': 'msha.gov', 'title': 'msha.gov'}]},
        {'id': 'f1', 'kind': 'REACT', 'title': 'If you see smoke', 'body': 'Keep low, move against the smoke towards intake air.', 'steps': ['Keep low'], 'hazardCategory': 'FIRE_SMOKE', 'sources': [{'domain': 'hse.gov.uk', 'title': 'hse.gov.uk'}]},
        {'id': 'p1', 'kind': 'PREVENT', 'title': 'Bar down loose roof', 'body': 'Test and bar down loose roof before every advance.', 'steps': ['Sound the roof'], 'hazardCategory': 'ROOF_FALL', 'sources': [{'domain': 'osha.gov', 'title': 'osha.gov'}]},
        {'id': 'x1', 'kind': 'MYSTERY', 'title': 'Unknown kind', 'body': 'Ignored by older apps.'},
      ],
      'videos': [
        {'kind': 'storyboard', 'itemId': 'g1', 'title': 'If you smell gas', 'frames': ['Stop work, warn others.', 'Put on the self-rescuer', 'Walk to intake air']},
        {'kind': 'veo', 'itemId': 'g1', 'title': 'No link yet'},
      ],
    };

class _Server implements HttpClientAdapter {
  _Server(this.answer);
  (int, Object) Function() answer;
  int hits = 0;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    hits++;
    final (code, body) = answer();
    return ResponseBody.fromString(jsonEncode(body), code, headers: {Headers.contentTypeHeader: ['application/json']});
  }
}

(ApiClient, SocketService, CacheRepository) _wire(_Server s) => (
      ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = s),
      SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x'),
      MemoryCacheRepository(),
    );

Future<void> until(bool Function() ok) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('parsing skips unknown kinds and clips without a link', () {
    final f = SafetyFeed.fromJson(feedJson());
    expect(f.items.length, 4);
    expect(f.of(SafetyItemKind.react).length, 2);
    expect(f.videos.single.kind, 'storyboard');
  });

  test('503 without a key is "not configured"; offline with a saved feed is "cached"', () async {
    final server = _Server(() => (503, {'error': {'code': 'FEED_NOT_CONFIGURED', 'message': 'x'}}));
    final (api, _, cache) = _wire(server);
    final repo = SafetyFeedRepository(api: api, cache: cache);
    expect((await repo.today()).availability, FeedAvailability.notConfigured);
    server.answer = () => (200, {'feed': feedJson()});
    expect((await repo.today()).availability, FeedAvailability.live);
    server.answer = () => (500, {'error': {'code': 'INTERNAL', 'message': 'x'}});
    final r = await repo.today();
    expect(r.availability, FeedAvailability.cached);
    expect(r.feed!.items.length, 4);
  });

  test('a safety:feed event reloads the feed', () async {
    var v = 1;
    final server = _Server(() => (200, {'feed': feedJson(version: v)}));
    final (api, socket, cache) = _wire(server);
    final bloc = SafetyFeedBloc(repo: SafetyFeedRepository(api: api, cache: cache), socket: socket)..add(const SafetyFeedStarted());
    await until(() => bloc.state.feed?.version == 1 && !bloc.state.loading);
    v = 2;
    socket.inject(SocketEvents.safetyFeed, {'date': '2026-10-17', 'version': 2}, id: 'sf2');
    await until(() => bloc.state.feed?.version == 2);
    await bloc.close();
  });

  Future<void> pump(WidgetTester tester, Widget home, {Size size = const Size(360, 780), bool dark = false, (int, Object) Function()? answer}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (api, socket, cache) = _wire(_Server(answer ?? () => (200, {'feed': feedJson()})));
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [RepositoryProvider<ApiClient>.value(value: api), RepositoryProvider<SocketService>.value(value: socket), RepositoryProvider<CacheRepository>.value(value: cache)],
      child: MaterialApp(theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]), home: home),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('safety bar shows today\'s titles with their kind and rotates', (tester) async {
    await pump(tester, const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: SafetyBar())));
    expect(find.text('Check your self-rescuer seal'), findsOneWidget);
    expect(find.text('Rule of the day'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('If you smell gas'), findsOneWidget);
  });

  testWidgets('safety bar without a configured feed says so instead of inventing rules', (tester) async {
    await pump(tester, const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: SafetyBar())), answer: () => (503, {'error': {'code': 'FEED_NOT_CONFIGURED', 'message': 'x'}}));
    expect(find.textContaining('not set up on the server'), findsOneWidget);
  });

  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets('safety screen at ${size.width.toInt()}px dark=$dark: every tab renders without overflow', (tester) async {
        await pump(tester, const SafetyScreen(), size: size, dark: dark);
        expect(find.text('Check your self-rescuer seal'), findsOneWidget);
        expect(find.textContaining('AI summary from dgms.gov.in'), findsOneWidget);
        await tester.tap(find.text('React'));
        await frames(tester);
        expect(find.text('Gas leak'), findsOneWidget);
        expect(find.text('Fire smoke'), findsOneWidget);
        await tester.tap(find.text('Prevent'));
        await frames(tester);
        expect(find.text('Bar down loose roof'), findsOneWidget);
        await tester.tap(find.text('Videos'));
        await frames(tester);
        expect(find.text('AI-generated explainer'), findsOneWidget);
        await tester.tap(find.byTooltip('Next'));
        await frames(tester);
        expect(find.text('Put on the self-rescuer'), findsOneWidget);
      });
    }
  }
}
