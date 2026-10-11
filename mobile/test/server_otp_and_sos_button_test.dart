import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart' show AuthFailure;
import 'package:mine_guardian/core/auth/otp_service.dart';
import 'package:mine_guardian/core/auth/server_otp_service.dart';
import 'package:mine_guardian/features/worker/widgets/sos_button.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.onPost) : super(tokenProvider: ({bool forceRefresh = false}) async => 't');
  final Map<String, dynamic> Function(String path, Object? body) onPost;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> postJson(String path, {Object? body, Map<String, dynamic>? query}) async {
    calls.add(path);
    return onPost(path, body);
  }
}

void main() {
  group('ServerOtpService', () {
    test('send posts nothing but the token (the server mails the signed-in login email); verify posts only the code', () async {
      final bodies = <Object?>[];
      final api = _FakeApi((p, b) {
        bodies.add(b);
        return {'sent': true, 'to': 'a***@example.com'};
      });
      final svc = ServerOtpService(api: api);
      final s = await svc.send('asha@example.com');
      expect(s.maskedTarget, 'a***@example.com');
      await svc.confirm(s, '123456');
      expect(api.calls, ['/api/auth/otp/send', '/api/auth/otp/verify']);
      expect(bodies, [null, {'code': '123456'}]);
    });

    test('server error codes become the messages the login flow understands', () async {
      Future<AuthFailure> failWith(String code) async {
        final svc = ServerOtpService(api: _FakeApi((p, b) => throw ApiException(code: code, message: 'm', statusCode: 400)));
        try {
          await svc.confirm(const OtpSession(email: 'asha@example.com'), '000000');
        } on AuthFailure catch (f) {
          return f;
        }
        fail('expected AuthFailure');
      }

      expect((await failWith('WRONG_CODE')).code, 'WRONG_CODE');
      expect((await failWith('CODE_EXPIRED')).code, 'CODE_EXPIRED');
      expect((await failWith('TOO_MANY_ATTEMPTS')).code, 'TOO_MANY_ATTEMPTS');
    });

  });

  group('SosButton hold', () {
    Future<int> holdFor(WidgetTester tester, Duration d) async {
      var triggered = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SosButton(onTriggered: () => triggered++)))));
      final g = await tester.startGesture(tester.getCenter(find.byType(SosButton)));
      await tester.pump(); // the ticker starts timing on its first frame
      await tester.pump(d);
      await tester.pump();
      await g.up();
      await tester.pump();
      return triggered;
    }

    testWidgets('holding for 2 seconds sends once (the long-press arena no longer cancels it at 500 ms)', (tester) async {
      expect(await holdFor(tester, const Duration(milliseconds: 2100)), 1);
    });

    testWidgets('releasing early sends nothing', (tester) async {
      expect(await holdFor(tester, const Duration(milliseconds: 1200)), 0);
    });
  });
}
