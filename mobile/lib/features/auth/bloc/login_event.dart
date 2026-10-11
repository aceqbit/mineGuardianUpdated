import 'package:equatable/equatable.dart';

import '../../../contracts/enums.dart';

sealed class LoginEvent extends Equatable {
  const LoginEvent();
  @override
  List<Object?> get props => [];
}

class RoleSelected extends LoginEvent {
  const RoleSelected(this.role);
  final Role role;
  @override
  List<Object?> get props => [role];
}

/// Step 1: email + password. On success a code is emailed to that address and step 2 begins.
class SubmitPressed extends LoginEvent {
  const SubmitPressed({required this.email, required this.password});
  final String email;
  final String password;
  @override
  List<Object?> get props => [email];
}

class MismatchSwitchRequested extends LoginEvent {
  const MismatchSwitchRequested();
}

/// The code the user typed. Never kept in state.
class OtpCodeSubmitted extends LoginEvent {
  const OtpCodeSubmitted(this.code);
  final String code;
}

class OtpResendRequested extends LoginEvent {
  const OtpResendRequested();
}

/// Leaves step 2: signs out and returns to the number + password form.
class OtpCancelled extends LoginEvent {
  const OtpCancelled();
}
