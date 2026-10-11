import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../config.dart';
import '../../../contracts/enums.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/otp_service.dart';
import '../../../core/auth/server_otp_service.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/models/session_user.dart';
import '../../../core/push/push_registrar.dart';
import '../data/email_validator.dart';
import '../data/password_rules.dart';
import 'login_event.dart';
import 'login_state.dart';

/// Two-step login. Step 1: email + password. Step 2: a code emailed to that same address. The session only starts after a
/// valid code; every other outcome (wrong role, wrong code 5 times, cancel, send failure) signs the user out again.
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc({required AuthRepository auth, required ApiClient api, required SessionBloc session, required PushRegistrar push, OtpService? otp, bool? otpGate})
      : _auth = auth,
        _api = api,
        _session = session,
        _push = push,
        _otp = otp ?? ServerOtpService(api: api),
        _otpGate = otpGate ?? otpRequired,
        super(const LoginState()) {
    on<RoleSelected>((e, emit) => emit(state.copyWith(role: e.role, clearError: true, clearMismatch: true)));
    on<MismatchSwitchRequested>((e, emit) {
      final actual = state.mismatchActualRole;
      if (actual != null) emit(state.copyWith(role: actual, clearError: true, clearMismatch: true));
    });
    on<SubmitPressed>(_onSubmit);
    on<OtpCodeSubmitted>(_onCode);
    on<OtpResendRequested>(_onResend);
    on<OtpCancelled>(_onCancel);
  }

  final AuthRepository _auth;
  final ApiClient _api;
  final SessionBloc _session;
  final PushRegistrar _push;
  final OtpService _otp;
  final bool _otpGate;

  OtpSession? _otpSession;
  SessionUser? _pendingUser; // password and role are fine; waiting for the code

  static String _mask(String email) {
    final at = email.indexOf('@');
    return at <= 1 ? email : '${email[0]}***${email.substring(at)}';
  }

  // ---------------------------------------------------------------- step 1: email + password

  Future<void> _onSubmit(SubmitPressed e, Emitter<LoginState> emit) async {
    if (state.status == LoginStatus.submitting || state.otp != OtpPhase.none) return;
    final emailError = validateEmail(e.email);
    if (emailError != null) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: emailError));
      return;
    }
    final pw = PasswordRules.evaluate(e.password);
    if (!pw.isValid) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: pw.firstError));
      return;
    }
    final email = normalizeEmail(e.email);
    emit(state.copyWith(status: LoginStatus.submitting, clearError: true, clearMismatch: true));
    try {
      await _auth.signIn(email, e.password);
      final user = await _loadUser(); // checks role / active before any email is sent
      if (!_otpGate) {
        _start(user, emit);
        return;
      }
      _pendingUser = user;
      await _sendCode(email, emit);
    } on AuthFailure catch (f) {
      await _abort(emit, f.message);
    } on ApiException catch (ex) {
      await _failApi(ex, emit);
    } catch (_) {
      await _abort(emit, 'Something went wrong. Please try again');
    }
  }

  Future<SessionUser> _loadUser() async {
    final json = await _api.getJson('/api/auth/me', query: {'expectedRole': state.role.wire});
    return SessionUser.fromMe(json);
  }

  void _start(SessionUser user, Emitter<LoginState> emit) {
    _pendingUser = null;
    _otpSession = null;
    emit(state.copyWith(status: LoginStatus.success, otp: OtpPhase.none));
    _session.add(LoggedIn(user));
    _push.register();
  }

  /// Signs out and returns to step 1 with a message. The only way back from any failure after the password step.
  Future<void> _abort(Emitter<LoginState> emit, String message) async {
    _pendingUser = null;
    _otpSession = null;
    try {
      await _auth.signOut();
    } catch (_) {}
    emit(state.copyWith(status: LoginStatus.failure, otp: OtpPhase.none, errorMessage: message));
  }

  Future<void> _failApi(ApiException ex, Emitter<LoginState> emit) async {
    _pendingUser = null;
    _otpSession = null;
    try {
      await _auth.signOut();
    } catch (_) {}
    switch (ex.code) {
      case 'ROLE_MISMATCH':
        final actual = (ex.details is Map ? (ex.details as Map)['actualRole'] : null) as String?;
        emit(state.copyWith(status: LoginStatus.failure, otp: OtpPhase.none, mismatchActualRole: actual == null ? null : Role.fromWire(actual)));
      case 'USER_NOT_REGISTERED':
        emit(state.copyWith(status: LoginStatus.failure, otp: OtpPhase.none, errorMessage: 'Account setup is incomplete — sign up again'));
      case 'ACCOUNT_INACTIVE':
        emit(state.copyWith(status: LoginStatus.failure, otp: OtpPhase.none, errorMessage: 'This account is inactive. Contact your mine admin'));
      case 'NETWORK':
        emit(state.copyWith(status: LoginStatus.failure, otp: OtpPhase.none, errorMessage: 'No connection — check your internet'));
      default:
        emit(state.copyWith(status: LoginStatus.failure, otp: OtpPhase.none, errorMessage: ex.message));
    }
  }

  // ---------------------------------------------------------------- step 2: emailed code

  Future<void> _sendCode(String email, Emitter<LoginState> emit) async {
    try {
      final s = await _otp.send(email);
      _otpSession = s;
      emit(state.copyWith(
        status: LoginStatus.idle,
        otp: OtpPhase.awaitingCode,
        cooldownUntil: DateTime.now().add(otpResendCooldown),
        attemptsLeft: otpMaxAttempts,
        maskedEmail: s.maskedTarget ?? _mask(email),
        clearError: true,
      ));
    } on AuthFailure catch (f) {
      await _abort(emit, f.message);
    } catch (_) {
      await _abort(emit, 'Could not send the code. Please try again');
    }
  }

  Future<void> _onResend(OtpResendRequested e, Emitter<LoginState> emit) async {
    final s = _otpSession;
    final wait = state.cooldownUntil;
    if (s == null || state.otp != OtpPhase.awaitingCode || state.status == LoginStatus.submitting) return;
    if (wait != null && DateTime.now().isBefore(wait)) return;
    emit(state.copyWith(status: LoginStatus.submitting, clearError: true));
    await _sendCode(s.email, emit);
  }

  Future<void> _onCancel(OtpCancelled e, Emitter<LoginState> emit) async {
    await _abort(emit, 'Login cancelled');
    emit(state.copyWith(status: LoginStatus.idle, clearError: true));
  }

  Future<void> _onCode(OtpCodeSubmitted e, Emitter<LoginState> emit) async {
    final session = _otpSession;
    final user = _pendingUser;
    if (session == null || user == null || state.otp != OtpPhase.awaitingCode || state.status == LoginStatus.submitting) return;
    final code = e.code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: 'Enter the 6-digit code'));
      return;
    }
    emit(state.copyWith(status: LoginStatus.submitting, clearError: true));
    try {
      await _otp.confirm(session, code);
      _start(user, emit);
    } on AuthFailure catch (f) {
      if (f.code == 'WRONG_CODE') {
        final left = state.attemptsLeft - 1;
        if (left <= 0) {
          await _abort(emit, 'Too many wrong codes. Please log in again');
        } else {
          emit(state.copyWith(status: LoginStatus.failure, errorMessage: 'That code is not correct. $left ${left == 1 ? 'try' : 'tries'} left', attemptsLeft: left));
        }
      } else if (f.code == 'CODE_EXPIRED') {
        emit(state.copyWith(status: LoginStatus.failure, errorMessage: f.message)); // user can resend once the wait ends
      } else {
        await _abort(emit, f.message);
      }
    } catch (_) {
      await _abort(emit, 'Something went wrong. Please try again');
    }
  }
}
