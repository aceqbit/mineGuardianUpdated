import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/otp_service.dart';
import 'package:mine_guardian/core/auth/session_bloc.dart';
import 'package:mine_guardian/core/push/push_registrar.dart';
import 'package:mine_guardian/features/auth/bloc/login_bloc.dart';
import 'package:mine_guardian/features/auth/bloc/login_event.dart';
import 'package:mine_guardian/features/auth/bloc/login_state.dart';

class _Auth implements AuthRepository {
  int signOuts = 0;
  @override
  Future<void> signIn(String e164, String password) async {}
  @override
  Future<void> signOut() async => signOuts++;
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  get currentUser => null;
}

class _Push implements PushRegistrar {
  @override
  Future<void> register() async {}
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Otp implements OtpService {
  _Otp({this.linked = false});
  bool linked;
  Object? sendError;
  String correct = '123456';
  AuthFailure? confirmError;
  int sends = 0;
  final sentLinking = <bool>[];

  @override
  bool get phoneLinked => linked;

  @override
  Future<OtpSession> send(String e164, {bool link = false, int? resendToken}) async {
    sends++;
    sentLinking.add(link);
    if (sendError != null) throw sendError!;
    return OtpSession(e164: e164, linking: link, verificationId: 'v', resendToken: 7);
  }

  @override
  Future<void> confirm(OtpSession s, String code) async {
    if (confirmError != null) throw confirmError!;
    if (code != correct) throw AuthFailure('WRONG_CODE', 'wrong');
  }

  @override
  Future<void> signOut() async {}
}

class _MeAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? r, Future<void>? c) async => ResponseBody.fromString(
        jsonEncode({'user': {'id': 'u1', 'role': 'miner', 'fullName': 'Asha', 'employeeId': 'MIN-0101', 'phone': {'e164': '+919876500101'}}}),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
}

void main() {
  late _Auth auth;
  late _Otp otp;
  late SessionBloc session;
  late LoginBloc bloc;

  void setUpBloc({bool linked = false}) {
    auth = _Auth();
    otp = _Otp(linked: linked);
    final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = _MeAdapter());
    session = SessionBloc(auth: auth, api: api);
    bloc = LoginBloc(auth: auth, api: api, session: session, push: _Push(), otp: otp);
  }

  Future<LoginState> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (var i = 0; i < 100 && bloc.state.status == LoginStatus.submitting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return bloc.state;
  }

  test('password login with an unlinked phone offers OTP, and skipping starts the session', () async {
    setUpBloc();
    bloc.add(const SubmitPressed(isoCode: 'IN', national: '9876500101', password: 'Miner1'));
    var s = await settle();
    expect(s.otp, OtpPhase.linkOffer);
    expect(s.maskedPhone, '••••0101');
    expect(session.state, isNot(isA<SessionAuthenticated>()));
    bloc.add(const OtpLinkSkipped());
    s = await settle();
    expect(s.status, LoginStatus.success);
    expect(session.state, isA<SessionAuthenticated>());
  });

  test('already-linked phone logs straight in with no offer', () async {
    setUpBloc(linked: true);
    bloc.add(const SubmitPressed(isoCode: 'IN', national: '9876500101', password: 'Miner1'));
    final s = await settle();
    expect(s.status, LoginStatus.success);
    expect(s.otp, OtpPhase.none);
  });

  test('link offer: code sent in link mode, correct code completes login', () async {
    setUpBloc();
    bloc.add(const SubmitPressed(isoCode: 'IN', national: '9876500101', password: 'Miner1'));
    await settle();
    bloc.add(const OtpLinkAccepted());
    var s = await settle();
    expect(s.otp, OtpPhase.linkAwaitingCode);
    expect(otp.sentLinking, [true]);
    bloc.add(const OtpCodeSubmitted('123456'));
    s = await settle();
    expect(s.status, LoginStatus.success);
  });

  test('link send failure keeps the offer so the user can skip', () async {
    setUpBloc();
    otp.sendError = AuthFailure('OTP_UNAVAILABLE', 'OTP login is not available right now. Use your password');
    bloc.add(const SubmitPressed(isoCode: 'IN', national: '9876500101', password: 'Miner1'));
    await settle();
    bloc.add(const OtpLinkAccepted());
    final s = await settle();
    expect(s.otp, OtpPhase.linkOffer);
    expect(s.errorMessage, contains('not available'));
    bloc.add(const OtpLinkSkipped());
    expect((await settle()).status, LoginStatus.success);
  });

  test('OTP login: send, wrong codes count down, 5th wrong code forces a new request', () async {
    setUpBloc();
    bloc.add(const LoginMethodChanged(LoginMethod.otp));
    bloc.add(const OtpSendRequested(isoCode: 'IN', national: '9876500101'));
    var s = await settle();
    expect(s.otp, OtpPhase.awaitingCode);
    expect(s.cooldownUntil!.isAfter(DateTime.now()), isTrue);
    for (var i = 4; i >= 1; i--) {
      bloc.add(const OtpCodeSubmitted('000000'));
      s = await settle();
      expect(s.errorMessage, contains('$i ${i == 1 ? 'try' : 'tries'} left'));
      expect(s.otp, OtpPhase.awaitingCode);
    }
    bloc.add(const OtpCodeSubmitted('000000'));
    s = await settle();
    expect(s.otp, OtpPhase.none);
    expect(s.errorMessage, contains('Too many wrong codes'));
    expect(s.attemptsLeft, otpMaxAttempts);
  });

  test('OTP login: malformed code is rejected locally, correct code logs in', () async {
    setUpBloc();
    bloc.add(const OtpSendRequested(isoCode: 'IN', national: '9876500101'));
    await settle();
    bloc.add(const OtpCodeSubmitted('12ab'));
    var s = await settle();
    expect(s.errorMessage, 'Enter the 6-digit code');
    bloc.add(const OtpCodeSubmitted('123456'));
    s = await settle();
    expect(s.status, LoginStatus.success);
    expect(session.state, isA<SessionAuthenticated>());
  });

  test('OTP for a number with no linked account is refused with a message that never mentions email', () async {
    setUpBloc();
    otp.confirmError = AuthFailure('OTP_NOT_ENABLED', 'OTP login is not set up for this number yet. Log in with your password once to enable it');
    bloc.add(const OtpSendRequested(isoCode: 'IN', national: '9876500101'));
    await settle();
    bloc.add(const OtpCodeSubmitted('123456'));
    final s = await settle();
    expect(s.otp, OtpPhase.none);
    expect(s.errorMessage!.toLowerCase(), isNot(contains('email')));
    expect(session.state, isNot(isA<SessionAuthenticated>()));
  });

  test('invalid phone never reaches the SMS service', () async {
    setUpBloc();
    bloc.add(const OtpSendRequested(isoCode: 'IN', national: '12345'));
    final s = await settle();
    expect(s.status, LoginStatus.failure);
    expect(otp.sends, 0);
  });
}
