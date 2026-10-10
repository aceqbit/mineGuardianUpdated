import 'package:equatable/equatable.dart';

import '../../../contracts/enums.dart';
import 'login_state.dart';

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

class SubmitPressed extends LoginEvent {
  const SubmitPressed({required this.isoCode, required this.national, required this.password});
  final String? isoCode;
  final String national;
  final String password;
  @override
  List<Object?> get props => [isoCode, national];
}

class MismatchSwitchRequested extends LoginEvent {
  const MismatchSwitchRequested();
}

class LoginMethodChanged extends LoginEvent {
  const LoginMethodChanged(this.method);
  final LoginMethod method;
  @override
  List<Object?> get props => [method];
}

/// Send an SMS code to the typed number (OTP login).
class OtpSendRequested extends LoginEvent {
  const OtpSendRequested({required this.isoCode, required this.national});
  final String? isoCode;
  final String national;
  @override
  List<Object?> get props => [isoCode, national];
}

class OtpResendRequested extends LoginEvent {
  const OtpResendRequested();
}

/// Back to the number step.
class OtpChangeNumber extends LoginEvent {
  const OtpChangeNumber();
}

/// The code the user typed. Never kept in state.
class OtpCodeSubmitted extends LoginEvent {
  const OtpCodeSubmitted(this.code);
  final String code;
}

/// After a password login: send a code to link this phone so OTP login works next time.
class OtpLinkAccepted extends LoginEvent {
  const OtpLinkAccepted();
}

class OtpLinkSkipped extends LoginEvent {
  const OtpLinkSkipped();
}
