import 'package:firebase_auth/firebase_auth.dart';

import 'phone_identity.dart';

/// Thrown with a user-safe message. Never mentions "email".
class AuthFailure implements Exception {
  AuthFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<String?> idToken({bool forceRefresh = false}) async => _auth.currentUser?.getIdToken(forceRefresh);

  Future<void> signIn(String e164, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: loginEmailFor(e164), password: password);
    } on FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  /// Creates the Firebase identity for sign-up. `email-already-in-use` -> code ALREADY_REGISTERED.
  Future<void> createAccount(String e164, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: loginEmailFor(e164), password: password);
    } on FirebaseAuthException catch (e) {
      throw _friendly(e);
    }
  }

  /// Rollback used when the profile save fails after [createAccount].
  Future<void> deleteCurrentFirebaseUser() async {
    try {
      await _auth.currentUser?.delete();
    } catch (_) {
      await _auth.signOut();
    }
  }

  Future<void> signOut() => _auth.signOut();

  AuthFailure _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return AuthFailure('INVALID_CREDENTIALS', 'Phone number or password is incorrect');
      case 'too-many-requests':
        return AuthFailure('TOO_MANY_REQUESTS', 'Too many attempts. Please wait a moment and try again');
      case 'network-request-failed':
        return AuthFailure('NETWORK', 'No connection — check your internet');
      case 'email-already-in-use':
        return AuthFailure('ALREADY_REGISTERED', 'This phone number is already registered — log in instead');
      case 'weak-password':
        return AuthFailure('WEAK_PASSWORD', 'Password must be 6 characters with a letter and a digit');
      case 'user-disabled':
        return AuthFailure('ACCOUNT_INACTIVE', 'This account has been disabled. Contact your supervisor');
      default:
        return AuthFailure('UNKNOWN', 'Something went wrong (${e.code}). Please try again');
    }
  }
}
