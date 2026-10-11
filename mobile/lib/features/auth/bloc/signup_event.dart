import 'package:equatable/equatable.dart';

import '../data/signup_repository.dart';

sealed class SignupEvent extends Equatable {
  const SignupEvent();
  @override
  List<Object?> get props => [];
}

class SignupStarted extends SignupEvent {
  const SignupStarted();
}

/// Partial update of non-text form values (selections, dates, switches). Text lives in controllers.
class SignupFieldsChanged extends SignupEvent {
  const SignupFieldsChanged({
    this.role,
    this.mineName,
    this.zoneId,
    this.shift,
    this.designation,
    this.experienceYears,
    this.dateOfJoining,
    this.dob,
    this.bloodGroup,
    this.consent,
  });
  final String? role;
  final String? mineName;
  final String? zoneId;
  final String? shift;
  final String? designation;
  final int? experienceYears;
  final DateTime? dateOfJoining;
  final DateTime? dob;
  final String? bloodGroup;
  final bool? consent;
  @override
  List<Object?> get props => [role, mineName, zoneId, shift, designation, experienceYears, dateOfJoining, dob, bloodGroup, consent];
}

class SignupStepChanged extends SignupEvent {
  const SignupStepChanged(this.step);
  final int step;
  @override
  List<Object?> get props => [step];
}

class SignupSubmitted extends SignupEvent {
  const SignupSubmitted(this.data);
  final SignupData data;
}

/// The SMS code typed during sign-up. Never kept in state.
class SignupOtpSubmitted extends SignupEvent {
  const SignupOtpSubmitted(this.code);
  final String code;
}

class SignupOtpResendRequested extends SignupEvent {
  const SignupOtpResendRequested();
}

/// Abandon verification: the just-created account is deleted and the form is shown again.
class SignupOtpCancelled extends SignupEvent {
  const SignupOtpCancelled();
}
