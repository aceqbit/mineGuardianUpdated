import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../config.dart';
import 'auth_repository.dart' show AuthFailure;
import 'otp_service.dart';

/// The code currently shown in the DEMO banner (null when none is pending).
class DemoOtp {
  DemoOtp._();
  static final ValueNotifier<String?> code = ValueNotifier<String?>(null);
}

/// Presentation-only stand-in for SMS: makes a random 6-digit code, shows it on screen, and checks it.
/// The sign-in flow around it (gate, 5 tries, cooldown, rollback on failure) is exactly the real one.
/// Nothing is sent to any phone. Enable with --dart-define=OTP_MODE=demo.
class DemoOtpService implements OtpService {
  DemoOtpService({Random? random}) : _rnd = random ?? Random.secure();
  final Random _rnd;

  @override
  bool get phoneLinked => false;

  @override
  OtpPurpose get purpose => OtpPurpose.link;

  static String _hash(String code, String e164) => sha256.convert(utf8.encode('$code|$e164')).toString();

  @override
  Future<OtpSession> send(String e164, {required OtpPurpose purpose, int? resendToken}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600)); // feels like a network round trip
    final code = (100000 + _rnd.nextInt(900000)).toString();
    DemoOtp.code.value = code;
    return OtpSession(e164: e164, purpose: purpose, verificationId: _hash(code, e164), resendToken: 1);
  }

  @override
  Future<void> confirm(OtpSession s, String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (s.verificationId == null || _hash(code, s.e164) != s.verificationId) {
      throw AuthFailure('WRONG_CODE', 'That code is not correct');
    }
    DemoOtp.code.value = null;
  }

  @override
  Future<void> signOut() async {
    DemoOtp.code.value = null;
  }
}

/// The OTP service for the configured mode.
OtpService createOtpService({String? mode}) => (mode ?? otpMode) == 'demo' ? DemoOtpService() : OtpService();
