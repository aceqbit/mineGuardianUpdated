import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../config.dart';
import '../../../contracts/enums.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/otp_service.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/models/session_user.dart';
import '../../../core/push/push_registrar.dart';
import '../data/password_rules.dart';
import '../data/phone_validator.dart';
import 'login_event.dart';
import 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc({required AuthRepository auth, required ApiClient api, required SessionBloc session, required PushRegistrar push, OtpService? otp})
      : _auth = auth,
        _api = api,
        _session = session,
        _push = push,
        _otp = otp ?? OtpService(),
        super(const LoginState()) {
    on<RoleSelected>((e, emit) => emit(state.copyWith(role: e.role, clearError: true, clearMismatch: true)));
    on<MismatchSwitchRequested>((e, emit) {
      final actual = state.mismatchActualRole;
      if (actual != null) emit(state.copyWith(role: actual, clearError: true, clearMismatch: true));
    });
    on<SubmitPressed>(_onSubmit);
    on<LoginMethodChanged>((e, emit) {
      if (state.otp == OtpPhase.linkOffer || state.otp == OtpPhase.linkAwaitingCode) return; // finish or skip the offer first
      emit(state.copyWith(method: e.method, otp: OtpPhase.none, clearError: true, clearMismatch: true));
    });
    on<OtpSendRequested>(_onSend);
    on<OtpResendRequested>(_onResend);
    on<OtpChangeNumber>((e, emit) => emit(state.copyWith(otp: OtpPhase.none, clearError: true)));
    on<OtpCodeSubmitted>(_onCode);
    on<OtpLinkAccepted>(_onLinkAccepted);
    on<OtpLinkSkipped>((e, emit) => _complete(emit));
  }

  final AuthRepository _auth;
  final ApiClient _api;
  final SessionBloc _session;
  final PushRegistrar _push;
  final OtpService _otp;

  OtpSession? _otpSession;
  SessionUser? _pendingUser; // password login done, waiting on the "enable OTP" offer

  static String _mask(String e164) => e164.length <= 4 ? e164 : '••••${e164.substring(e164.length - 4)}';

  // ---------------------------------------------------------------- password login

  Future<void> _onSubmit(SubmitPressed e, Emitter<LoginState> emit) async {
    if (state.status == LoginStatus.submitting) return;
    final phone = validatePhone(e.isoCode, e.national);
    if (!phone.isValid) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: phone.error));
      return;
    }
    final pw = PasswordRules.evaluate(e.password);
    if (!pw.isValid) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: pw.firstError));
      return;
    }
    emit(state.copyWith(status: LoginStatus.submitting, clearError: true, clearMismatch: true));
    try {
      await _auth.signIn(phone.e164!, e.password);
      final user = await _loadUser();
      if (otpLinkPrompt && !_otp.phoneLinked) {
        // Offer OTP login for next time. The session only starts once the user answers.
        _pendingUser = user;
        _otpSession = null;
        emit(state.copyWith(status: LoginStatus.idle, otp: OtpPhase.linkOffer, maskedPhone: _mask(phone.e164!)));
        return;
      }
      _start(user, emit);
    } on AuthFailure catch (f) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: f.message));
    } on ApiException catch (ex) {
      await _failApi(ex, emit);
    } catch (_) {
      await _auth.signOut();
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: 'Something went wrong. Please try again'));
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

  void _complete(Emitter<LoginState> emit) {
    final u = _pendingUser;
    if (u != null) _start(u, emit);
  }

  Future<void> _failApi(ApiException ex, Emitter<LoginState> emit) async {
    await _auth.signOut();
    _pendingUser = null;
    _otpSession = null;
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

  // ---------------------------------------------------------------- OTP

  Future<void> _onSend(OtpSendRequested e, Emitter<LoginState> emit) async {
    if (state.status == LoginStatus.submitting) return;
    final phone = validatePhone(e.isoCode, e.national);
    if (!phone.isValid) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: phone.error));
      return;
    }
    final wait = state.cooldownUntil;
    if (wait != null && DateTime.now().isBefore(wait) && state.maskedPhone == _mask(phone.e164!)) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: 'Please wait before requesting another code'));
      return;
    }
    await _sendTo(phone.e164!, emit, link: false);
  }

  Future<void> _onResend(OtpResendRequested e, Emitter<LoginState> emit) async {
    final s = _otpSession;
    final wait = state.cooldownUntil;
    if (s == null || state.status == LoginStatus.submitting) return;
    if (wait != null && DateTime.now().isBefore(wait)) return;
    await _sendTo(s.e164, emit, link: s.linking, token: s.resendToken);
  }

  Future<void> _onLinkAccepted(OtpLinkAccepted e, Emitter<LoginState> emit) async {
    final u = _pendingUser;
    if (u == null || state.status == LoginStatus.submitting) return;
    await _sendTo(u.phoneE164, emit, link: true);
  }

  Future<void> _sendTo(String e164, Emitter<LoginState> emit, {required bool link, int? token}) async {
    emit(state.copyWith(status: LoginStatus.submitting, clearError: true, clearMismatch: true));
    try {
      final s = await _otp.send(e164, link: link, resendToken: token);
      _otpSession = s;
      emit(state.copyWith(
        status: LoginStatus.idle,
        otp: link ? OtpPhase.linkAwaitingCode : OtpPhase.awaitingCode,
        cooldownUntil: DateTime.now().add(otpResendCooldown),
        attemptsLeft: otpMaxAttempts,
        maskedPhone: _mask(e164),
      ));
      if (s.instantCredential != null) add(const OtpCodeSubmitted('')); // Firebase verified the phone without a code
    } on AuthFailure catch (f) {
      // Failing to send must never trap a user who already passed the password step.
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: f.message, otp: link ? OtpPhase.linkOffer : OtpPhase.none));
    } catch (_) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: 'Could not send the code. Please try again', otp: link ? OtpPhase.linkOffer : OtpPhase.none));
    }
  }

  Future<void> _onCode(OtpCodeSubmitted e, Emitter<LoginState> emit) async {
    final session = _otpSession;
    if (session == null || state.status == LoginStatus.submitting) return;
    final code = e.code.trim();
    if (session.instantCredential == null && !RegExp(r'^\d{6}$').hasMatch(code)) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: 'Enter the 6-digit code'));
      return;
    }
    emit(state.copyWith(status: LoginStatus.submitting, clearError: true, clearMismatch: true));
    try {
      await _otp.confirm(session, code);
      if (session.linking) {
        _complete(emit); // phone linked; the password session is already valid
      } else {
        _start(await _loadUser(), emit);
      }
    } on AuthFailure catch (f) {
      if (f.code == 'WRONG_CODE') {
        final left = state.attemptsLeft - 1;
        if (left <= 0) {
          _otpSession = null;
          emit(state.copyWith(
            status: LoginStatus.failure,
            errorMessage: 'Too many wrong codes. Request a new code',
            otp: session.linking ? OtpPhase.linkOffer : OtpPhase.none,
            attemptsLeft: otpMaxAttempts,
            cooldownUntil: DateTime.now().add(otpResendCooldown * 2),
          ));
        } else {
          emit(state.copyWith(status: LoginStatus.failure, errorMessage: 'That code is not correct. $left ${left == 1 ? 'try' : 'tries'} left', attemptsLeft: left));
        }
      } else if (session.linking) {
        // Linking is optional: show why, and let the user retry or skip.
        emit(state.copyWith(status: LoginStatus.failure, errorMessage: f.message, otp: f.code == 'CODE_EXPIRED' ? OtpPhase.linkOffer : OtpPhase.linkAwaitingCode));
      } else {
        emit(state.copyWith(status: LoginStatus.failure, errorMessage: f.message, otp: f.code == 'CODE_EXPIRED' || f.code == 'OTP_NOT_ENABLED' ? OtpPhase.none : OtpPhase.awaitingCode));
      }
    } on ApiException catch (ex) {
      await _failApi(ex, emit);
    } catch (_) {
      await _auth.signOut();
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: 'Something went wrong. Please try again', otp: OtpPhase.none));
    }
  }
}
