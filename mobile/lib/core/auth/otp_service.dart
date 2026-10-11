/// One emailed-code exchange. Holds only where the code went (masked by the server), never the code itself.
class OtpSession {
  const OtpSession({required this.email, this.maskedTarget});
  final String email;

  /// Where the code went, already masked by the server (a***@gmail.com).
  final String? maskedTarget;
}

/// Emailed one-time codes. The user is already signed in with email and password when a code is sent; a valid code
/// finishes the login (or sign-up) and anything else ends in sign-out.
abstract class OtpService {
  /// Emails a fresh code to the signed-in login email.
  Future<OtpSession> send(String email);

  /// Checks the code. Throws an `AuthFailure` with a user-safe message when it is wrong, expired or refused.
  Future<void> confirm(OtpSession session, String code);

  Future<void> signOut();
}
