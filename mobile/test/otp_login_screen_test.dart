import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/session_bloc.dart';
import 'package:mine_guardian/features/auth/bloc/login_state.dart';
import 'package:mine_guardian/features/auth/view/login_screen.dart';
import 'package:mine_guardian/features/auth/widgets/otp_panels.dart';

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  get currentUser => null;
}

void main() {
  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets('login SMS-code tab fits at ${size.width.toInt()}px dark=$dark and starts empty', (tester) async {
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
            child: MaterialApp(theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]), home: const LoginScreen()),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('SMS code'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('Send code'), findsOneWidget);
        expect(find.text('Log in as Miner'), findsNothing);
        for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
          expect(f.controller!.text, isEmpty);
        }
        // Sending with no number shakes and shows the phone error instead of calling Firebase.
        await tester.ensureVisible(find.text('Send code'));
        await tester.tap(find.text('Send code'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('Send code'), findsOneWidget);
      });
    }
  }

  testWidgets('code entry enables Verify only for 6 digits and drops non-digits', (tester) async {
    String? sent;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: const [MgColors.light]),
      home: Scaffold(
        body: SingleChildScrollView(
          child: OtpCodeEntry(
            state: LoginState(otp: OtpPhase.awaitingCode, maskedPhone: '••••0101', cooldownUntil: DateTime.now().add(const Duration(seconds: 30))),
            secondaryLabel: 'Change number',
            onVerify: (c) => sent = c,
            onResend: () {},
            onSecondary: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Resend code in'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12a34');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '1234');
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Verify code'));
    await tester.pump();
    expect(sent, '123456');
  });
}
