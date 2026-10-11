import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/session_bloc.dart';
import 'package:mine_guardian/features/auth/view/login_screen.dart';

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  get currentUser => null;
}

void main() {
  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    testWidgets('login renders without overflow at ${size.width.toInt()}px, starts empty', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = _FakeAuth();
      final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null);
      final session = SessionBloc(auth: auth, api: api);
      await tester.pumpWidget(MultiRepositoryProvider(
        providers: [RepositoryProvider<AuthRepository>.value(value: auth), RepositoryProvider<ApiClient>.value(value: api)],
        child: BlocProvider<SessionBloc>.value(
          value: session,
          child: MaterialApp(theme: ThemeData(useMaterial3: true, extensions: const [MgColors.light]), home: const LoginScreen()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Email address'), findsOneWidget); // email only: no country code, no phone field
      expect(find.text('Code'), findsNothing);
      expect(find.text('Mobile number'), findsNothing);
      expect(find.text('Miner Login'), findsOneWidget);
      expect(find.text('Supervisor Login'), findsOneWidget);
      expect(find.text('Admin Login'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      for (final f in fields) {
        expect(f.controller!.text, isEmpty);
      }
    });
  }
}
