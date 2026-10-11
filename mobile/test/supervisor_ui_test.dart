import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/app/ui/net_photo.dart';
import 'package:mine_guardian/contracts/enums.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/session_bloc.dart';
import 'package:mine_guardian/core/models/session_user.dart';
import 'package:mine_guardian/core/socket/socket_service.dart';
import 'package:mine_guardian/features/supervisor_home/data/models/feed_item.dart';
import 'package:mine_guardian/features/supervisor_home/view/supervisor_home_screen.dart';
import 'package:mine_guardian/features/supervisor_home/widgets/workers_page.dart';

WorkerToday w(String id, String name, String status, {Verdict? verdict, Verdict? finalVerdict, String? thumb}) =>
    WorkerToday(id: id, fullName: name, employeeId: 'MIN-$id', status: status, verdict: verdict, finalVerdict: finalVerdict, thumbUrl: thumb, count: status == 'NOT_CHECKED_IN' ? 0 : 1);

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  get currentUser => null;
}

/// Serves one supervisor snapshot; everything else (risk bands, ...) is 404 = "not available yet".
class _Server implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (o.path == '/api/feed/supervisor') {
      final body = {
        'zone': {'id': 'zB', 'code': 'Z-B', 'name': 'Zone B — Central Panel'},
        'workers': [
          {'id': 'a', 'fullName': 'Ravi Kumar', 'employeeId': 'MIN-0105', 'today': {'status': 'NOT_CHECKED_IN', 'count': 0}},
          {'id': 'b', 'fullName': 'Asha Devi', 'employeeId': 'MIN-0106', 'today': {'status': 'PREDICTED', 'verdict': 'COMPLIANT', 'count': 1, 'capturedAt': '2026-01-01T10:00:00Z'}},
        ],
        'checkins': [],
        'hazards': [],
        'sos': [],
      };
      return ResponseBody.fromString(jsonEncode(body), 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }
    return ResponseBody.fromString(jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'nf'}}), 404, headers: {Headers.contentTypeHeader: ['application/json']});
  }
}

void main() {
  group('worker roster filter', () {
    final all = [
      w('1', 'Ravi Kumar', 'NOT_CHECKED_IN'),
      w('2', 'Asha Devi', 'PREDICTED', verdict: Verdict.compliant),
      w('3', 'Mohan Singh', 'REVIEWED', finalVerdict: Verdict.nonCompliant),
      w('4', 'Anil Mahato', 'REVIEWED', finalVerdict: Verdict.compliant),
    ];

    test('each chip picks the right workers', () {
      expect(filterWorkers(all, WorkerFilter.all, '').length, 4);
      expect(filterWorkers(all, WorkerFilter.notCheckedIn, '').map((x) => x.id), ['1']);
      expect(filterWorkers(all, WorkerFilter.needsReview, '').map((x) => x.id), ['2']);
      expect(filterWorkers(all, WorkerFilter.nonCompliant, '').map((x) => x.id), ['3']);
    });

    test('search matches name or employee ID, case-insensitively, and combines with the chip', () {
      expect(filterWorkers(all, WorkerFilter.all, 'mohan').map((x) => x.id), ['3']);
      expect(filterWorkers(all, WorkerFilter.all, 'min-4').map((x) => x.id), ['4']);
      expect(filterWorkers(all, WorkerFilter.notCheckedIn, 'asha'), isEmpty);
    });
  });

  group('photos', () {
    test('a re-signed link for the same file has the same cache key, so a loaded photo survives link expiry', () {
      const a = 'http://localhost:4000/files/Y2hlY2tpbnMvYS5qcGc.1791761772497.sigONE';
      const b = 'http://localhost:4000/files/Y2hlY2tpbnMvYS5qcGc.1791999999999.sigTWO';
      expect(photoCacheKey(a), photoCacheKey(b));
      expect(photoCacheKey('http://localhost:4000/files/OTHER.1.x'), isNot(photoCacheKey(a)));
    });

    test('other hosts key on the URL without its changing query', () {
      expect(photoCacheKey('https://storage.example.com/p/a.jpg?X-Goog-Signature=1'), photoCacheKey('https://storage.example.com/p/a.jpg?X-Goog-Signature=2'));
    });

    test('the snapshot carries the latest photo, time and count for each worker', () {
      final x = WorkerToday.fromJson({
        'id': 'b', 'fullName': 'Asha', 'employeeId': 'MIN-1',
        'today': {'status': 'PREDICTED', 'checkInId': 'c1', 'capturedAt': '2026-01-01T10:00:00Z', 'thumbUrl': 'http://x/files/abc.1.s', 'count': 2},
      });
      expect(x.thumbUrl, 'http://x/files/abc.1.s');
      expect(x.count, 2);
      expect(x.capturedAt, DateTime.utc(2026, 1, 1, 10));
    });
  });

  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets('supervisor home at ${size.width.toInt()}px dark=$dark: Live Feed and Workers are different pages, no overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = _Server();
        final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: dio);
        final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x');
        final session = SessionBloc(auth: _FakeAuth(), api: api)
          ..add(const LoggedIn(SessionUser(id: 'u9', role: Role.supervisor, fullName: 'Sunil Banerjee', employeeId: 'SUP-0012', phoneE164: '', zoneId: 'zB', zoneCode: 'Z-B', zoneName: 'Zone B — Central Panel', shift: Shift.a)));
        await tester.pumpWidget(MultiRepositoryProvider(
          providers: [RepositoryProvider<ApiClient>.value(value: api), RepositoryProvider<SocketService>.value(value: socket)],
          child: BlocProvider<SessionBloc>.value(
            value: session,
            child: MaterialApp(
              theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]),
              home: const SupervisorHomeScreen(),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 800));

        // Live Feed page: the feed and the zone pulse, no roster search.
        expect(find.text('Live feed'), findsOneWidget);
        expect(find.text('Zone pulse'), findsOneWidget);
        expect(find.text('Search by name or employee ID'), findsNothing);
        expect(find.text('Review next'), findsOneWidget);

        // Workers page: the roster with search, filter chips and worker cards. The feed is gone.
        await tester.tap(find.text('Workers').first);
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('Search by name or employee ID'), findsOneWidget);
        expect(find.text('Ravi Kumar'), findsOneWidget);
        expect(find.text('Asha Devi'), findsOneWidget);
        expect(find.text('Live feed'), findsNothing);
        expect(find.textContaining('Not checked in ·'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500)); // let the staggered entrance timers fire before the tree is disposed

      });
    }
  }
}
