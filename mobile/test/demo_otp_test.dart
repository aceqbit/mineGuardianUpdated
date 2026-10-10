import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/demo_otp_service.dart';
import 'package:mine_guardian/core/auth/otp_service.dart';
import 'package:mine_guardian/features/auth/widgets/otp_panels.dart';

void main() {
  tearDown(() => DemoOtp.code.value = null);

  test('demo send makes a 6-digit code, shows it, and only that code confirms', () async {
    final svc = DemoOtpService(random: Random(1));
    final s = await svc.send('+919790773117', purpose: OtpPurpose.link);
    final code = DemoOtp.code.value!;
    expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
    await expectLater(svc.confirm(s, code == '123456' ? '654321' : '123456'), throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'WRONG_CODE')));
    expect(DemoOtp.code.value, code); // a wrong try does not clear it
    await svc.confirm(s, code);
    expect(DemoOtp.code.value, isNull);
  });

  test('the code is bound to the phone number and each send is a new code', () async {
    final svc = DemoOtpService();
    final a = await svc.send('+919790773117', purpose: OtpPurpose.link);
    final codeA = DemoOtp.code.value!;
    final other = OtpSession(e164: '+919999999999', purpose: OtpPurpose.link, verificationId: a.verificationId);
    await expectLater(svc.confirm(other, codeA), throwsA(isA<AuthFailure>()));
    final b = await svc.send('+919790773117', purpose: OtpPurpose.link, resendToken: 1);
    expect(b.verificationId, isNot(a.verificationId));
  });

  test('factory returns the demo service only in demo mode', () {
    expect(createOtpService(mode: 'demo'), isA<DemoOtpService>());
    expect(createOtpService(mode: 'firebase'), isNot(isA<DemoOtpService>()));
  });

  testWidgets('the DEMO banner appears with the code and disappears when cleared', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: const [MgColors.light]),
      home: Scaffold(body: SingleChildScrollView(child: OtpCodeEntry(maskedPhone: '••••3117', cooldownUntil: null, busy: false, secondaryLabel: 'x', onVerify: (_) {}, onResend: () {}, onSecondary: () {}))),
    ));
    expect(find.textContaining('DEMO MODE'), findsNothing);
    DemoOtp.code.value = '482913';
    await tester.pump();
    expect(find.textContaining('482913'), findsOneWidget);
    DemoOtp.code.value = null;
    await tester.pump();
    expect(find.textContaining('DEMO MODE'), findsNothing);
  });
}
