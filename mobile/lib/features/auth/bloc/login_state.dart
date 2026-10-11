import 'package:equatable/equatable.dart';

import '../../../contracts/enums.dart';

enum LoginStatus { idle, submitting, failure, success }

/// Step 1 is email + password; step 2 is the emailed code. Nothing proceeds without a valid code.
enum OtpPhase { none, awaitingCode }

/// Wrong codes allowed before the user must log in again.
const int otpMaxAttempts = 5;

/// Minimum wait before another code can be requested.
const Duration otpResendCooldown = Duration(seconds: 30);

/// Form text lives in widget controllers, never here.
class LoginState extends Equatable {
  const LoginState({this.role = Role.miner, this.status = LoginStatus.idle, this.errorMessage, this.mismatchActualRole, this.otp = OtpPhase.none, this.cooldownUntil, this.attemptsLeft = otpMaxAttempts, this.maskedEmail});
  final Role role;
  final LoginStatus status;
  final String? errorMessage;
  final Role? mismatchActualRole;
  final OtpPhase otp;
  final DateTime? cooldownUntil;
  final int attemptsLeft;
  final String? maskedEmail;

  LoginState copyWith({Role? role, LoginStatus? status, String? errorMessage, Role? mismatchActualRole, OtpPhase? otp, DateTime? cooldownUntil, int? attemptsLeft, String? maskedEmail, bool clearError = false, bool clearMismatch = false}) => LoginState(
        role: role ?? this.role,
        status: status ?? this.status,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        mismatchActualRole: clearMismatch ? null : (mismatchActualRole ?? this.mismatchActualRole),
        otp: otp ?? this.otp,
        cooldownUntil: cooldownUntil ?? this.cooldownUntil,
        attemptsLeft: attemptsLeft ?? this.attemptsLeft,
        maskedEmail: maskedEmail ?? this.maskedEmail,
      );

  @override
  List<Object?> get props => [role, status, errorMessage, mismatchActualRole, otp, cooldownUntil, attemptsLeft, maskedEmail];
}
