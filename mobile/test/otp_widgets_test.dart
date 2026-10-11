import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/features/auth/widgets/otp_panels.dart';

void main() {
  for (final size in const [Size(360, 780), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets('stepper and code entry fit at ${size.width.toInt()}px dark=$dark', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        String? sent;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(children: [
                const OtpStepper(step: 1),
                const SizedBox(height: Space.lg),
                OtpCodeEntry(
                  maskedEmail: 'a***@example.com',
                  cooldownUntil: DateTime.now().add(const Duration(seconds: 30)),
                  busy: false,
                  secondaryLabel: 'Use a different email',
                  onVerify: (c) => sent = c,
                  onResend: () {},
                  onSecondary: () {},
                ),
              ]),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Resend code in'), findsOneWidget);
        expect(find.textContaining('a***@example.com'), findsOneWidget);
        // Starts empty, accepts digits only, Verify enabled only at 6 digits.
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
        await tester.enterText(find.byType(TextField), '12a34');
        await tester.pump();
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '1234');
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();
        await tester.tap(find.text('Verify and continue'));
        await tester.pump();
        expect(sent, '123456');
      });
    }
  }

  testWidgets('code entry is empty again after a new code is sent', (tester) async {
    final first = DateTime.now().add(const Duration(seconds: 30));
    Widget host(DateTime until) => MaterialApp(
          theme: ThemeData(useMaterial3: true, extensions: const [MgColors.light]),
          home: Scaffold(body: SingleChildScrollView(child: OtpCodeEntry(maskedEmail: 'a***@example.com', cooldownUntil: until, busy: false, secondaryLabel: 'x', onVerify: (_) {}, onResend: () {}, onSecondary: () {}))),
        );
    await tester.pumpWidget(host(first));
    await tester.enterText(find.byType(TextField), '123');
    await tester.pumpWidget(host(first.add(const Duration(seconds: 40))));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });
}
