import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../config.dart';
import '../../../core/auth/auth_repository.dart' show AuthFailure;
import '../../../core/auth/otp_service.dart';
import '../data/signup_repository.dart';
import 'login_state.dart' show otpMaxAttempts, otpResendCooldown;
import 'signup_event.dart';
import 'signup_state.dart';

/// Sign-up: Firebase account, then an SMS code that proves the phone, then the profile. If the phone is not verified
/// for any reason the new Firebase account is deleted again (no orphans).
class SignupBloc extends Bloc<SignupEvent, SignupState> {
  SignupBloc({required SignupRepository repo, OtpService? otp, bool? otpGate})
      : _repo = repo,
        _otp = otp ?? OtpService(),
        _otpGate = otpGate ?? otpRequired,
        super(const SignupState()) {
    on<SignupStarted>(_onStarted);
    on<SignupFieldsChanged>(_onFields);
    on<SignupStepChanged>((e, emit) => emit(state.copyWith(step: e.step.clamp(0, 2), clearError: true)));
    on<SignupSubmitted>(_onSubmit);
    on<SignupOtpSubmitted>(_onCode);
    on<SignupOtpResendRequested>(_onResend);
    on<SignupOtpCancelled>(_onCancel);
  }

  final SignupRepository _repo;
  final OtpService _otp;
  final bool _otpGate;

  SignupData? _data;
  OtpSession? _session;

  static String _mask(String e164) => e164.length <= 4 ? e164 : '••••${e164.substring(e164.length - 4)}';

  Future<void> _onStarted(SignupStarted e, Emitter<SignupState> emit) async {
    emit(state.copyWith(status: SignupStatus.loadingZones));
    try {
      final zones = await _repo.zones();
      emit(state.copyWith(status: SignupStatus.idle, zones: zones));
    } catch (_) {
      emit(state.copyWith(status: SignupStatus.zonesFailed));
    }
  }

  void _onFields(SignupFieldsChanged e, Emitter<SignupState> emit) {
    final mineChanged = e.mineName != null && e.mineName != state.mineName;
    emit(state.copyWith(
      role: e.role,
      mineName: e.mineName,
      clearZone: mineChanged,
      zoneId: mineChanged ? null : e.zoneId,
      shift: e.shift,
      designation: e.designation,
      experienceYears: e.experienceYears,
      dateOfJoining: e.dateOfJoining,
      dob: e.dob,
      bloodGroup: e.bloodGroup,
      relation: e.relation,
      consent: e.consent,
    ));
  }

  Future<void> _onSubmit(SignupSubmitted e, Emitter<SignupState> emit) async {
    if (state.status == SignupStatus.submitting || state.status == SignupStatus.verifying) return;
    emit(state.copyWith(status: SignupStatus.submitting, clearError: true, progressLabel: 'Creating account…', alreadyRegistered: false));
    try {
      if (!_otpGate) {
        final user = await _repo.register(e.data, onStage: (s) => emit(state.copyWith(progressLabel: s)));
        emit(state.copyWith(status: SignupStatus.success, user: user));
        return;
      }
      await _repo.createAccount(e.data);
      _data = e.data;
      emit(state.copyWith(progressLabel: 'Sending code…'));
      await _sendCode(e.data.e164, emit);
    } on SignupFailure catch (f) {
      emit(state.copyWith(status: SignupStatus.failure, errorMessage: f.message, errorStep: f.step, step: f.step, alreadyRegistered: f.alreadyRegistered));
    } catch (e) {
      // Anything unexpected after the account may have been created: never leave an orphan Firebase user behind.
      debugPrint('signup failed: $e');
      try {
        await _repo.discardAccount();
      } catch (_) {}
      _session = null;
      _data = null;
      emit(state.copyWith(status: SignupStatus.failure, errorMessage: 'Something went wrong (${e.runtimeType}). Please try again', errorStep: 0, step: 0, clearOtp: true));
    }
  }

  Future<void> _sendCode(String e164, Emitter<SignupState> emit, {int? token}) async {
    try {
      final s = await _otp.send(e164, purpose: OtpPurpose.link, resendToken: token);
      _session = s;
      emit(state.copyWith(
        status: SignupStatus.verifying,
        otpMasked: _mask(e164),
        otpCooldownUntil: DateTime.now().add(otpResendCooldown),
        otpAttemptsLeft: otpMaxAttempts,
        clearError: true,
      ));
      if (s.instantCredential != null) add(const SignupOtpSubmitted(''));
    } on AuthFailure catch (f) {
      await _rollback(emit, f.message);
    } catch (_) {
      await _rollback(emit, 'Could not send the code. Please try again');
    }
  }

  /// Phone not verified: delete the Firebase account and return to the form on the account step.
  Future<void> _rollback(Emitter<SignupState> emit, String message) async {
    _session = null;
    _data = null;
    try {
      await _repo.discardAccount();
    } catch (_) {}
    emit(state.copyWith(status: SignupStatus.failure, errorMessage: message, errorStep: 0, step: 0, clearOtp: true));
  }

  Future<void> _onResend(SignupOtpResendRequested e, Emitter<SignupState> emit) async {
    final s = _session;
    final wait = state.otpCooldownUntil;
    if (s == null || state.status != SignupStatus.verifying) return;
    if (wait != null && DateTime.now().isBefore(wait)) return;
    await _sendCode(s.e164, emit, token: s.resendToken);
  }

  Future<void> _onCancel(SignupOtpCancelled e, Emitter<SignupState> emit) async {
    if (state.status != SignupStatus.verifying) return;
    _session = null;
    _data = null;
    try {
      await _repo.discardAccount();
    } catch (_) {}
    emit(state.copyWith(status: SignupStatus.idle, clearError: true, clearOtp: true));
  }

  Future<void> _onCode(SignupOtpSubmitted e, Emitter<SignupState> emit) async {
    final session = _session;
    final data = _data;
    if (session == null || data == null || state.status != SignupStatus.verifying) return;
    final code = e.code.trim();
    if (session.instantCredential == null && !RegExp(r'^\d{6}$').hasMatch(code)) {
      emit(state.copyWith(errorMessage: 'Enter the 6-digit code', errorStep: 0));
      return;
    }
    emit(state.copyWith(status: SignupStatus.submitting, progressLabel: 'Verifying…', clearError: true));
    try {
      await _otp.confirm(session, code);
      emit(state.copyWith(progressLabel: 'Saving profile…'));
      final user = await _repo.completeRegistration(data);
      _session = null;
      _data = null;
      emit(state.copyWith(status: SignupStatus.success, user: user, clearOtp: true));
    } on AuthFailure catch (f) {
      if (f.code == 'WRONG_CODE') {
        final left = state.otpAttemptsLeft - 1;
        if (left <= 0) {
          await _rollback(emit, 'Too many wrong codes. Please start again');
        } else {
          emit(state.copyWith(status: SignupStatus.verifying, errorMessage: 'That code is not correct. $left ${left == 1 ? 'try' : 'tries'} left', errorStep: 0, otpAttemptsLeft: left));
        }
      } else if (f.code == 'CODE_EXPIRED') {
        emit(state.copyWith(status: SignupStatus.verifying, errorMessage: f.message, errorStep: 0));
      } else {
        await _rollback(emit, f.message);
      }
    } on SignupFailure catch (f) {
      // completeRegistration already deleted the Firebase user.
      _session = null;
      _data = null;
      emit(state.copyWith(status: SignupStatus.failure, errorMessage: f.message, errorStep: f.step, step: f.step, clearOtp: true));
    } catch (_) {
      await _rollback(emit, 'Something went wrong. Please try again');
    }
  }
}
