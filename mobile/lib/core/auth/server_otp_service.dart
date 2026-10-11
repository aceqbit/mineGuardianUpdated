import '../api/api_client.dart';
import 'auth_repository.dart' show AuthFailure;
import 'otp_service.dart';

/// Email code sent and checked by our backend (POST /api/auth/otp/send and /verify). The server mails the code to the
/// signed-in login email; the app never sends an address. The code only ever travels by email: the API never returns it,
/// and it is never shown on screen, stored or logged.
class ServerOtpService implements OtpService {
  ServerOtpService({required ApiClient api}) : _api = api;
  final ApiClient _api;

  @override
  Future<OtpSession> send(String email) async {
    try {
      final r = await _api.postJson('/api/auth/otp/send');
      return OtpSession(email: email, maskedTarget: r['to'] as String?);
    } on ApiException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> confirm(OtpSession session, String code) async {
    try {
      await _api.postJson('/api/auth/otp/verify', body: {'code': code});
    } on ApiException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> signOut() async {}

  AuthFailure _friendly(ApiException e) {
    switch (e.code) {
      case 'WRONG_CODE':
        return AuthFailure('WRONG_CODE', 'That code is not correct');
      case 'CODE_EXPIRED':
        return AuthFailure('CODE_EXPIRED', 'That code has expired. Request a new one');
      case 'TOO_MANY_ATTEMPTS':
        return AuthFailure('TOO_MANY_ATTEMPTS', 'Too many wrong codes. Please log in again');
      case 'OTP_COOLDOWN':
      case 'OTP_LIMIT':
        return AuthFailure('TOO_MANY_REQUESTS', e.message);
      case 'NETWORK':
        return AuthFailure('NETWORK', 'No connection — check your internet');
      case 'OTP_NOT_CONFIGURED':
        return AuthFailure('OTP_UNAVAILABLE', 'Verification is not available right now. Please contact your admin');
      case 'OTP_SEND_FAILED':
        return AuthFailure('OTP_UNAVAILABLE', e.message);
      default:
        return AuthFailure('UNKNOWN', 'Could not send the code. Please try again');
    }
  }
}
