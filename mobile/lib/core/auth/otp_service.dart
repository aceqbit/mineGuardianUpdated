import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'auth_repository.dart' show AuthFailure;

/// Why a code is being sent: [link] attaches the phone to the signed-in account (first time),
/// [reauth] proves the same phone again on every later login.
enum OtpPurpose { link, reauth }

/// One SMS-code exchange. Holds Firebase's verification handle, never the code itself.
class OtpSession {
  const OtpSession({required this.e164, required this.purpose, this.verificationId, this.resendToken, this.web, this.instantCredential, this.uid});
  final String e164;
  final OtpPurpose purpose;
  final String? verificationId;
  final int? resendToken;
  final ConfirmationResult? web;

  /// Set when Firebase verified the phone instantly (no code needed).
  final PhoneAuthCredential? instantCredential;

  /// Firebase uid of the password account the code is for (used to detect a web re-verification landing on another user).
  final String? uid;
}

/// Phone OTP through Firebase Auth. The code is generated, sent and checked by Firebase over TLS, is single-use and
/// short-lived, and is never stored or logged by the app. The user is already signed in with their password when a code
/// is sent: a valid code links the phone (first time) or re-verifies it (every later login); anything else ends in sign-out.
class OtpService {
  OtpService({FirebaseAuth? auth}) : _auth = auth;
  FirebaseAuth? _auth;
  FirebaseAuth get _fb => _auth ??= FirebaseAuth.instance;

  bool get phoneLinked => _fb.currentUser?.providerData.any((p) => p.providerId == 'phone') ?? false;

  /// [OtpPurpose.reauth] when the phone is already linked to this account, else [OtpPurpose.link].
  OtpPurpose get purpose => phoneLinked ? OtpPurpose.reauth : OtpPurpose.link;

  /// Sends an SMS code to [e164] for the signed-in user.
  Future<OtpSession> send(String e164, {required OtpPurpose purpose, int? resendToken}) async {
    try {
      final user = _fb.currentUser;
      if (user == null) throw AuthFailure('UNKNOWN', 'Please log in again');
      if (kIsWeb) {
        // The web SDK has no phone re-authentication call: for an already-linked phone, confirming a phone sign-in lands on the same uid.
        final r = purpose == OtpPurpose.link ? await user.linkWithPhoneNumber(e164) : await _fb.signInWithPhoneNumber(e164);
        return OtpSession(e164: e164, purpose: purpose, web: r, uid: user.uid);
      }
      final done = Completer<OtpSession>();
      await _fb.verifyPhoneNumber(
        phoneNumber: e164,
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
        verificationCompleted: (cred) {
          // Android may verify instantly. Used only when no code SMS is needed; otherwise the user types the code.
          if (!done.isCompleted) done.complete(OtpSession(e164: e164, purpose: purpose, instantCredential: cred));
        },
        verificationFailed: (e) {
          if (!done.isCompleted) done.completeError(friendlyOtpError(e));
        },
        codeSent: (id, token) {
          if (!done.isCompleted) done.complete(OtpSession(e164: e164, purpose: purpose, verificationId: id, resendToken: token));
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return await done.future.timeout(const Duration(seconds: 40), onTimeout: () => throw AuthFailure('NETWORK', 'Could not send the code. Check your connection and try again'));
    } on FirebaseAuthException catch (e) {
      throw friendlyOtpError(e);
    }
  }

  /// Checks the code. Throws [AuthFailure] with a user-safe message when it is wrong, expired or refused.
  Future<void> confirm(OtpSession s, String code) async {
    try {
      if (s.web != null) {
        final res = await s.web!.confirm(code);
        final now = _fb.currentUser;
        if (s.purpose == OtpPurpose.reauth && now != null && s.uid != null && now.uid != s.uid) {
          // That phone belongs to nobody on this account: undo the sign-in it just created.
          if (res.additionalUserInfo?.isNewUser ?? false) {
            try {
              await now.delete();
            } catch (_) {}
          }
          await _fb.signOut();
          throw AuthFailure('PHONE_MISMATCH', 'This number does not match your account');
        }
        return;
      }
      final user = _fb.currentUser;
      if (user == null) throw AuthFailure('UNKNOWN', 'Please log in again');
      final cred = s.instantCredential ?? PhoneAuthProvider.credential(verificationId: s.verificationId!, smsCode: code);
      if (s.purpose == OtpPurpose.link) {
        await user.linkWithCredential(cred);
      } else {
        await user.reauthenticateWithCredential(cred);
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
    case 'user-mismatch':
      return AuthFailure('PHONE_MISMATCH', 'This number does not match your account');
    case 'user-disabled':
      return AuthFailure('ACCOUNT_INACTIVE', 'This account has been disabled. Contact your supervisor');
    case 'operation-not-allowed':
    case 'app-not-authorized':
    case 'missing-client-identifier':
      return AuthFailure('OTP_UNAVAILABLE', 'SMS verification is not available right now. Please contact your admin');
    default:
      return AuthFailure('UNKNOWN', 'Something went wrong. Please try again');
  }
}
