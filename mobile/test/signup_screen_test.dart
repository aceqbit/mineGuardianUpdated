import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/session_bloc.dart';
import 'package:mine_guardian/features/auth/view/signup_screen.dart';

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  get currentUser => null;
}

class _ZonesAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = jsonEncode([
      {'id': 'z1', '_id': 'z1', 'code': 'Z-A', 'name': 'Zone A', 'mineName': 'MG Demo Colliery'},
      {'id': 'z2', '_id': 'z2', 'code': 'Z-B', 'name': 'Zone B', 'mineName': 'MG Demo Colliery'},
    ]);
    return ResponseBody.fromString(body, 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }
}

void main() {
  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    testWidgets('signup step 1 renders at ${size.width.toInt()}px and validates', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = _FakeAuth();
      final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = _ZonesAdapter();
      final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: dio);
      final session = SessionBloc(auth: auth, api: api);
      await tester.pumpWidget(MultiRepositoryProvider(
        providers: [RepositoryProvider<AuthRepository>.value(value: auth), RepositoryProvider<ApiClient>.value(value: api)],
        child: BlocProvider<SessionBloc>.value(
          value: session,
          child: MaterialApp(theme: ThemeData(useMaterial3: true, extensions: const [MgColors.light]), home: const SignupScreen()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Mobile number'), findsNothing);
      for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(f.controller!.text, isEmpty);
      }
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Enter your full name (2 to 60 characters)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
