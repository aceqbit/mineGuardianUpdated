import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'auth_repository.dart' show AuthFailure;

/// One SMS-code exchange. Holds Firebase's verification handle, never the code itself.
class OtpSession {
  const OtpSession({required this.e164, required this.linking, this.verificationId, this.resendToken, this.web, this.instantCredential});
  final String e164;

  /// True when the code links the phone to the signed-in account; false when it signs in.
  final bool linking;
  final String? verificationId;
  final int? resendToken;
  final ConfirmationResult? web;

  /// Set when Firebase verified the phone instantly (no code needed).
  final PhoneAuthCredential? instantCredential;
}

/// Phone OTP through Firebase Auth. The SMS code is generated, sent and checked by Firebase over TLS, is single-use and
/// short-lived, and is never stored or logged by the app. The Mongo user is keyed by the Firebase uid of the password
/// account, so OTP sign-in only works for a phone that was first *linked* to that account; a phone with no linked account
/// never creates a new (orphan) Firebase user.
class OtpService {
  OtpService({FirebaseAuth? auth}) : _auth = auth;
  FirebaseAuth? _auth;
  FirebaseAuth get _fb => _auth ??= FirebaseAuth.instance;

  bool get phoneLinked => _fb.currentUser?.providerData.any((p) => p.providerId == 'phone') ?? false;

  /// Sends an SMS code. With [link] the signed-in account gets the phone attached on success.
  Future<OtpSession> send(String e164, {bool link = false, int? resendToken}) async {
    try {
      if (kIsWeb) {
        final user = _fb.currentUser;
        final r = link && user != null ? await user.linkWithPhoneNumber(e164) : await _fb.signInWithPhoneNumber(e164);
        return OtpSession(e164: e164, linking: link, web: r);
      }
      final done = Completer<OtpSession>();
      await _fb.verifyPhoneNumber(
        phoneNumber: e164,
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
        verificationCompleted: (cred) {
          // Android may verify instantly. Only used when no code SMS was needed; otherwise the user types the code.
          if (!done.isCompleted) done.complete(OtpSession(e164: e164, linking: link, instantCredential: cred));
        },
        verificationFailed: (e) {
          if (!done.isCompleted) done.completeError(friendlyOtpError(e));
        },
        codeSent: (id, token) {
          if (!done.isCompleted) done.complete(OtpSession(e164: e164, linking: link, verificationId: id, resendToken: token));
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return await done.future.timeout(const Duration(seconds: 40), onTimeout: () => throw AuthFailure('NETWORK', 'Could not send the code. Check your connection and try again'));
    } on FirebaseAuthException catch (e) {
      throw friendlyOtpError(e);
    }
  }

  /// Checks the code and signs in (or links the phone). Throws [AuthFailure] with a user-safe message.
  Future<void> confirm(OtpSession s, String code) async {
    try {
      UserCredential? result;
      if (s.web != null) {
        result = await s.web!.confirm(code);
      } else {
        final cred = s.instantCredential ?? PhoneAuthProvider.credential(verificationId: s.verificationId!, smsCode: code);
        result = s.linking ? await _fb.currentUser!.linkWithCredential(cred) : await _fb.signInWithCredential(cred);
      }
      if (!s.linking && (result.additionalUserInfo?.isNewUser ?? false)) {
        // This phone was never linked to an account: remove the empty Firebase user that sign-in just created.
        try {
          await _fb.currentUser?.delete();
        } catch (_) {
          await _fb.signOut();
        }
        throw AuthFailure('OTP_NOT_ENABLED', 'OTP login is not set up for this number yet. Log in with your password once to enable it');
      }
    } on FirebaseAuthException catch (e) {
      throw friendlyOtpError(e);
    }
  }

  Future<void> signOut() => _fb.signOut();
}

AuthFailure friendlyOtpError(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-verification-code':
      return AuthFailure('WRONG_CODE', 'That code is not correct');
    case 'session-expired':
    case 'code-expired':
      return AuthFailure('CODE_EXPIRED', 'That code has expired. Request a new one');
    case 'invalid-phone-number':
      return AuthFailure('INVALID_PHONE', 'Enter a valid mobile number');
    case 'too-many-requests':
    case 'quota-exceeded':
      return AuthFailure('TOO_MANY_REQUESTS', 'Too many attempts. Please wait a while and try again');
    case 'network-request-failed':
      return AuthFailure('NETWORK', 'No connection — check your internet');
    case 'credential-already-in-use':
    case 'provider-already-linked':
    case 'account-exists-with-different-credential':
      return AuthFailure('PHONE_IN_USE', 'This number is already linked to another account');
    case 'user-disabled':
      return AuthFailure('ACCOUNT_INACTIVE', 'This account has been disabled. Contact your supervisor');
    case 'operation-not-allowed':
    case 'app-not-authorized':
    case 'missing-client-identifier':
      return AuthFailure('OTP_UNAVAILABLE', 'OTP login is not available right now. Use your password');
    default:
      return AuthFailure('UNKNOWN', 'Something went wrong. Please try again');
  }
}
