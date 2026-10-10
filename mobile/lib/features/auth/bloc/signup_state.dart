import 'package:equatable/equatable.dart';

import '../../../core/models/session_user.dart';
import '../data/signup_repository.dart';

enum SignupStatus { idle, loadingZones, zonesFailed, submitting, verifying, failure, success }

class SignupState extends Equatable {
  const SignupState({
    this.step = 0,
    this.status = SignupStatus.idle,
    this.zones = const [],
    this.role = 'miner',
    this.mineName,
    this.zoneId,
    this.shift,
    this.designation,
    this.experienceYears = 0,
    this.dateOfJoining,
    this.dob,
    this.bloodGroup,
    this.relation,
    this.consent = false,
    this.errorMessage,
    this.errorStep,
    this.alreadyRegistered = false,
    this.progressLabel,
    this.user,
    this.otpMasked,
    this.otpCooldownUntil,
    this.otpAttemptsLeft = 5,
  });

  final int step;
  final SignupStatus status;
  final List<ZoneOption> zones;
  final String role;
  final String? mineName;
  final String? zoneId;
  final String? shift;
  final String? designation;
  final int experienceYears;
  final DateTime? dateOfJoining;
  final DateTime? dob;
  final String? bloodGroup;
  final String? relation;
  final bool consent;
  final String? errorMessage;
  final int? errorStep;
  final bool alreadyRegistered;
  final String? progressLabel;
  final SessionUser? user;
  final String? otpMasked;
  final DateTime? otpCooldownUntil;
  final int otpAttemptsLeft;

  List<String> get mines => zones.map((z) => z.mineName).toSet().toList()..sort();
  List<ZoneOption> get zonesOfMine => zones.where((z) => z.mineName == mineName).toList();

  SignupState copyWith({
    int? step,
    SignupStatus? status,
    List<ZoneOption>? zones,
    String? role,
    String? mineName,
    bool clearZone = false,
    String? zoneId,
    String? shift,
    String? designation,
    int? experienceYears,
    DateTime? dateOfJoining,
    DateTime? dob,
    String? bloodGroup,
    String? relation,
    bool? consent,
    String? errorMessage,
    int? errorStep,
    bool clearError = false,
    bool? alreadyRegistered,
    String? progressLabel,
    SessionUser? user,
    String? otpMasked,
    DateTime? otpCooldownUntil,
    int? otpAttemptsLeft,
    bool clearOtp = false,
  }) =>
      SignupState(
        step: step ?? this.step,
        status: status ?? this.status,
        zones: zones ?? this.zones,
        role: role ?? this.role,
        mineName: mineName ?? this.mineName,
        zoneId: clearZone ? null : (zoneId ?? this.zoneId),
        shift: shift ?? this.shift,
        designation: designation ?? this.designation,
        experienceYears: experienceYears ?? this.experienceYears,
        dateOfJoining: dateOfJoining ?? this.dateOfJoining,
        dob: dob ?? this.dob,
        bloodGroup: bloodGroup ?? this.bloodGroup,
        relation: relation ?? this.relation,
        consent: consent ?? this.consent,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        errorStep: clearError ? null : (errorStep ?? this.errorStep),
        alreadyRegistered: alreadyRegistered ?? this.alreadyRegistered,
        progressLabel: progressLabel ?? this.progressLabel,
        user: user ?? this.user,
        otpMasked: clearOtp ? null : (otpMasked ?? this.otpMasked),
        otpCooldownUntil: otpCooldownUntil ?? this.otpCooldownUntil,
        otpAttemptsLeft: otpAttemptsLeft ?? this.otpAttemptsLeft,
      );

  @override
  List<Object?> get props => [step, status, zones, role, mineName, zoneId, shift, designation, experienceYears, dateOfJoining, dob, bloodGroup, relation, consent, errorMessage, errorStep, alreadyRegistered, progressLabel, user, otpMasked, otpCooldownUntil, otpAttemptsLeft];
}
