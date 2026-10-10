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
import 'package:mine_guardian/features/auth/bloc/signup_bloc.dart';
import 'package:mine_guardian/features/auth/bloc/signup_event.dart';
import 'package:mine_guardian/features/auth/bloc/signup_state.dart';
import 'package:mine_guardian/features/auth/data/signup_repository.dart';

class _Auth implements AuthRepository {
  int signOuts = 0;
  int signIns = 0;
  int created = 0;
  int deleted = 0;
  @override
  Future<void> signIn(String e164, String password) async => signIns++;
  @override
  Future<void> signOut() async => signOuts++;
  @override
  Future<void> createAccount(String e164, String password) async => created++;
  @override
  Future<void> deleteCurrentFirebaseUser() async => deleted++;
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
  AuthFailure? sendError;
  AuthFailure? confirmError;
  final String correct = '123456';
  int sends = 0;
  final purposes = <OtpPurpose>[];

  @override
  bool get phoneLinked => linked;
  @override
  OtpPurpose get purpose => linked ? OtpPurpose.reauth : OtpPurpose.link;

  @override
  Future<OtpSession> send(String e164, {required OtpPurpose purpose, int? resendToken}) async {
    sends++;
    purposes.add(purpose);
    if (sendError != null) throw sendError!;
    return OtpSession(e164: e164, purpose: purpose, verificationId: 'v', resendToken: 7);
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

ApiClient _api() => ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = _MeAdapter());

Future<void> _settle(bool Function() busy) async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  for (var i = 0; i < 100 && busy(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  group('login gate', () {
    late _Auth auth;
    late _Otp otp;
    late SessionBloc session;
    late LoginBloc bloc;

    void setUpBloc({bool linked = false, bool gate = true}) {
      auth = _Auth();
      otp = _Otp(linked: linked);
      final api = _api();
      session = SessionBloc(auth: auth, api: api);
      bloc = LoginBloc(auth: auth, api: api, session: session, push: _Push(), otp: otp, otpGate: gate);
    }

    Future<LoginState> settle() async {
      await _settle(() => bloc.state.status == LoginStatus.submitting);
      return bloc.state;
    }

    const submit = SubmitPressed(isoCode: 'IN', national: '9876500101', password: 'Miner1');

    test('password alone never starts the session: a code is sent and step 2 begins', () async {
      setUpBloc();
      bloc.add(submit);
      final s = await settle();
      expect(s.otp, OtpPhase.awaitingCode);
      expect(s.maskedPhone, '••••0101');
      expect(otp.sends, 1);
      expect(session.state, isNot(isA<SessionAuthenticated>()));
    });

    test('first login links the phone, later logins re-verify it', () async {
      setUpBloc();
      bloc.add(submit);
      await settle();
      expect(otp.purposes, [OtpPurpose.link]);
      setUpBloc(linked: true);
      bloc.add(submit);
      await settle();
      expect(otp.purposes, [OtpPurpose.reauth]);
    });

    test('a valid code starts the session', () async {
      setUpBloc();
      bloc.add(submit);
      await settle();
      bloc.add(const OtpCodeSubmitted('123456'));
      final s = await settle();
      expect(s.status, LoginStatus.success);
      expect(session.state, isA<SessionAuthenticated>());
    });

    test('a code before the password step is ignored', () async {
      setUpBloc();
      bloc.add(const OtpCodeSubmitted('123456'));
      final s = await settle();
      expect(s.status, LoginStatus.idle);
      expect(session.state, isNot(isA<SessionAuthenticated>()));
    });

    test('malformed code is rejected locally and the gate stays closed', () async {
      setUpBloc();
      bloc.add(submit);
      await settle();
      bloc.add(const OtpCodeSubmitted('12ab'));
      final s = await settle();
      expect(s.errorMessage, 'Enter the 6-digit code');
      expect(s.otp, OtpPhase.awaitingCode);
      expect(session.state, isNot(isA<SessionAuthenticated>()));
    });

    test('wrong codes count down and the 5th signs the user out', () async {
      setUpBloc();
      bloc.add(submit);
      await settle();
      for (var i = 4; i >= 1; i--) {
        bloc.add(const OtpCodeSubmitted('000000'));
        final s = await settle();
        expect(s.errorMessage, contains('$i ${i == 1 ? 'try' : 'tries'} left'));
        expect(s.otp, OtpPhase.awaitingCode);
      }
      bloc.add(const OtpCodeSubmitted('000000'));
      final s = await settle();
      expect(s.otp, OtpPhase.none);
      expect(s.errorMessage, contains('Too many wrong codes'));
      expect(auth.signOuts, greaterThan(0));
      expect(session.state, isNot(isA<SessionAuthenticated>()));
    });

    test('failing to send the code signs out instead of letting the user in', () async {
      setUpBloc();
      otp.sendError = AuthFailure('OTP_UNAVAILABLE', 'SMS verification is not available right now. Please contact your admin');
      bloc.add(submit);
      final s = await settle();
      expect(s.otp, OtpPhase.none);
      expect(s.status, LoginStatus.failure);
      expect(auth.signOuts, 1);
      expect(session.state, isNot(isA<SessionAuthenticated>()));
    });

    test('a refused code (number does not match) signs out; the message never mentions email', () async {
      setUpBloc();
      otp.confirmError = AuthFailure('PHONE_MISMATCH', 'This number does not match your account');
      bloc.add(submit);
      await settle();
      bloc.add(const OtpCodeSubmitted('123456'));
      final s = await settle();
      expect(s.otp, OtpPhase.none);
      expect(s.errorMessage!.toLowerCase(), isNot(contains('email')));
      expect(auth.signOuts, greaterThan(0));
    });

    test('cancel signs out and returns to step 1', () async {
      setUpBloc();
      bloc.add(submit);
      await settle();
      bloc.add(const OtpCancelled());
      final s = await settle();
      expect(s.otp, OtpPhase.none);
      expect(s.errorMessage, isNull);
      expect(auth.signOuts, 1);
    });

    test('resend is ignored during the cooldown', () async {
      setUpBloc();
      bloc.add(submit);
      await settle();
      bloc.add(const OtpResendRequested());
      await settle();
      expect(otp.sends, 1);
    });

    test('with the gate switched off (development) login goes straight in', () async {
      setUpBloc(gate: false);
      bloc.add(submit);
      final s = await settle();
      expect(s.status, LoginStatus.success);
      expect(otp.sends, 0);
    });

    test('invalid phone never reaches Firebase', () async {
      setUpBloc();
      bloc.add(const SubmitPressed(isoCode: 'IN', national: '12345', password: 'Miner1'));
      final s = await settle();
      expect(s.status, LoginStatus.failure);
      expect(auth.signIns, 0);
    });
  });

  group('sign-up gate', () {
    late _Auth auth;
    late _Otp otp;
    late SignupBloc bloc;

    SignupData data() => SignupData(
          role: 'miner',
          fullName: 'Asha Devi',
          employeeId: 'MIN-0999',
          isoCode: 'IN',
          dialCode: '+91',
          national: '9876500101',
          e164: '+919876500101',
          password: 'Miner1',
          mineName: 'MG Demo Colliery',
          zoneId: 'z1',
          shift: 'A',
          designation: 'Miner',
          experienceYears: 3,
          dateOfJoining: DateTime(2023, 1, 1),
          dob: DateTime(1995, 1, 1),
          bloodGroup: 'O+',
          emergencyName: 'Ravi',
          emergencyRelation: 'Brother',
          emergencyIso: 'IN',
          emergencyDial: '+91',
          emergencyNational: '9876500102',
        );

    void setUpBloc({bool gate = true}) {
      auth = _Auth();
      otp = _Otp();
      bloc = SignupBloc(repo: SignupRepository(auth: auth, api: _api()), otp: otp, otpGate: gate);
    }

    Future<SignupState> settle() async {
      await _settle(() => bloc.state.status == SignupStatus.submitting && bloc.state.otpMasked == null);
      return bloc.state;
    }

    test('account is created, a code is sent, and only a valid code finishes sign-up', () async {
      setUpBloc();
      bloc.add(SignupSubmitted(data()));
      var s = await settle();
      expect(s.status, SignupStatus.verifying);
      expect(s.otpMasked, '••••0101');
      expect(auth.created, 1);
      expect(otp.purposes, [OtpPurpose.link]);
      bloc.add(const SignupOtpSubmitted('123456'));
      await _settle(() => bloc.state.status == SignupStatus.submitting);
      s = bloc.state;
      expect(s.status, SignupStatus.success);
      expect(s.user, isNotNull);
      expect(auth.deleted, 0);
    });

    test('5 wrong codes delete the new Firebase account (no orphan) and return to the form', () async {
      setUpBloc();
      bloc.add(SignupSubmitted(data()));
      await settle();
      for (var i = 0; i < 5; i++) {
        bloc.add(const SignupOtpSubmitted('000000'));
        await _settle(() => bloc.state.status == SignupStatus.submitting);
      }
      final s = bloc.state;
      expect(s.status, SignupStatus.failure);
      expect(s.otpMasked, isNull);
      expect(auth.deleted, 1);
    });

    test('cancelling verification deletes the account', () async {
      setUpBloc();
      bloc.add(SignupSubmitted(data()));
      await settle();
      bloc.add(const SignupOtpCancelled());
      await _settle(() => false);
      expect(bloc.state.status, SignupStatus.idle);
      expect(auth.deleted, 1);
    });

    test('failing to send the code deletes the account', () async {
      setUpBloc();
      otp.sendError = AuthFailure('OTP_UNAVAILABLE', 'SMS verification is not available right now. Please contact your admin');
      bloc.add(SignupSubmitted(data()));
      await settle();
      expect(bloc.state.status, SignupStatus.failure);
      expect(auth.deleted, 1);
    });

    test('code before sign-up submit is ignored', () async {
      setUpBloc();
      bloc.add(const SignupOtpSubmitted('123456'));
      await _settle(() => false);
      expect(bloc.state.status, SignupStatus.idle);
    });
  });
}
