import 'package:equatable/equatable.dart';

import '../../../contracts/enums.dart';

enum LoginStatus { idle, submitting, failure, success }

enum LoginMethod { password, otp }

/// Where the OTP exchange is. `linkOffer` and `linkAwaitingCode` happen after a successful password login.
enum OtpPhase { none, awaitingCode, linkOffer, linkAwaitingCode }

/// Wrong codes allowed before the user must request a new one.
const int otpMaxAttempts = 5;

/// Minimum wait before another code can be requested.
const Duration otpResendCooldown = Duration(seconds: 30);

/// Form text lives in widget controllers, never here.
class LoginState extends Equatable {
  const LoginState({this.role = Role.miner, this.status = LoginStatus.idle, this.errorMessage, this.mismatchActualRole, this.method = LoginMethod.password, this.otp = OtpPhase.none, this.cooldownUntil, this.attemptsLeft = otpMaxAttempts, this.maskedPhone});
  final Role role;
  final LoginStatus status;
  final String? errorMessage;
  final Role? mismatchActualRole;
  final LoginMethod method;
  final OtpPhase otp;
  final DateTime? cooldownUntil;
  final int attemptsLeft;
  final String? maskedPhone;

  LoginState copyWith({Role? role, LoginStatus? status, String? errorMessage, Role? mismatchActualRole, LoginMethod? method, OtpPhase? otp, DateTime? cooldownUntil, int? attemptsLeft, String? maskedPhone, bool clearError = false, bool clearMismatch = false}) => LoginState(
        role: role ?? this.role,
        status: status ?? this.status,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        mismatchActualRole: clearMismatch ? null : (mismatchActualRole ?? this.mismatchActualRole),
        method: method ?? this.method,
        otp: otp ?? this.otp,
        cooldownUntil: cooldownUntil ?? this.cooldownUntil,
        attemptsLeft: attemptsLeft ?? this.attemptsLeft,
        maskedPhone: maskedPhone ?? this.maskedPhone,
      );

  @override
  List<Object?> get props => [role, status, errorMessage, mismatchActualRole, method, otp, cooldownUntil, attemptsLeft, maskedPhone];
}
