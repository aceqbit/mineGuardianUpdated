import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../config.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/otp_service.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/push/push_registrar.dart';
import '../bloc/login_bloc.dart';
import '../bloc/login_event.dart';
import '../bloc/login_state.dart';
import '../data/countries.dart';
import '../data/password_rules.dart';
import '../data/phone_validator.dart';
import '../widgets/country_code_picker.dart';
import '../widgets/login_hero.dart';
import '../widgets/otp_panels.dart';
import '../widgets/password_field.dart';
import '../widgets/phone_field.dart';
import '../widgets/role_switcher.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.otp});

  /// Override in tests; defaults to Firebase phone OTP.
  final OtpService? otp;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => LoginBloc(
        auth: ctx.read<AuthRepository>(),
        api: ctx.read<ApiClient>(),
        session: ctx.read<SessionBloc>(),
        push: PushRegistrar(api: ctx.read<ApiClient>()),
        otp: otp,
      ),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> with SingleTickerProviderStateMixin {
  // Everything starts empty: no default country, no pre-filled values, no timers.
  Country? _country;
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _codeFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _pwFocus = FocusNode();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  bool _phoneTouched = false;
  bool _pwTouched = false;
  bool _submitted = false;
  String _shakeTarget = '';

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(() {
      if (!_phoneFocus.hasFocus && _phone.text.isNotEmpty) setState(() => _phoneTouched = true);
    });
    _pwFocus.addListener(() {
      if (!_pwFocus.hasFocus && _password.text.isNotEmpty) setState(() => _pwTouched = true);
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _codeFocus.dispose();
    _phoneFocus.dispose();
    _pwFocus.dispose();
    _shake.dispose();
    super.dispose();
  }

  String? get _phoneError {
    if (!(_phoneTouched || _submitted)) return null;
    return validatePhone(_country?.isoCode, _phone.text).error;
  }

  String? get _pwError {
    if (!(_pwTouched || _submitted)) return null;
    return PasswordRules.evaluate(_password.text).firstError;
  }

  void _submit() {
    setState(() => _submitted = true);
    final phoneBad = validatePhone(_country?.isoCode, _phone.text).error != null;
    final pwBad = !PasswordRules.evaluate(_password.text).isValid;
    if (phoneBad || pwBad) {
      if (_country == null) {
        _shakeTarget = 'code';
        _codeFocus.requestFocus();
      } else if (phoneBad) {
        _shakeTarget = 'phone';
        _phoneFocus.requestFocus();
      } else {
        _shakeTarget = 'pw';
        _pwFocus.requestFocus();
      }
      if (!Motion.reduce(context)) _shake.forward(from: 0);
      return;
    }
    context.read<LoginBloc>().add(SubmitPressed(isoCode: _country?.isoCode, national: _phone.text, password: _password.text));
  }

  Widget _shaken(String id, Widget child) => AnimatedBuilder(
        animation: _shake,
        builder: (context, c) {
          final dx = _shakeTarget == id ? math.sin(_shake.value * 3 * 2 * math.pi) * 6 * (1 - _shake.value) : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: c);
        },
        child: child,
      );

  Widget _banner(BuildContext context, LoginState s) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    if (s.mismatchActualRole != null) {
      final actual = s.mismatchActualRole!;
      return Container(
        margin: const EdgeInsets.only(bottom: Space.lg),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(color: c.warningBg, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This number is registered as ${actual.label}. Switch to ${actual.label} Login.', style: t.bodyMedium?.copyWith(color: c.warning)),
          const SizedBox(height: Space.sm),
          MgButton(label: 'Switch to ${actual.label} Login', kind: MgButtonKind.secondary, onPressed: () => context.read<LoginBloc>().add(const MismatchSwitchRequested())),
        ]),
      );
    }
    if (s.errorMessage != null && s.status == LoginStatus.failure) {
      return Container(
        margin: const EdgeInsets.only(bottom: Space.lg),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(color: c.dangerBg, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Row(children: [
          Icon(Icons.error_outline, color: c.danger, size: 20),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(s.errorMessage!, style: t.bodyMedium?.copyWith(color: c.danger))),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _form(BuildContext context, LoginState s) {
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    final submitting = s.status == LoginStatus.submitting;
    final verifying = s.otp == OtpPhase.awaitingCode;
    final bloc = context.read<LoginBloc>();
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(verifying ? 'Verify it is you' : 'Welcome back', style: t.headlineMedium),
        const SizedBox(height: Space.xs),
        Text(verifying ? 'One more step to protect your account' : 'Log in with your mobile number', style: t.bodySmall),
        const SizedBox(height: Space.lg),
        OtpStepper(step: verifying ? 1 : 0),
        const SizedBox(height: Space.x2),
        if (!verifying) ...[
          RoleSwitcher(role: s.role, onChanged: (r) => bloc.add(RoleSelected(r))),
          const SizedBox(height: Space.x2),
        ],
        _banner(context, s),
        if (verifying)
          OtpCodeEntry(
            maskedPhone: s.maskedPhone,
            cooldownUntil: s.cooldownUntil,
            busy: submitting,
            secondaryLabel: 'Change number',
            onVerify: (code) => bloc.add(OtpCodeSubmitted(code)),
            onResend: () => bloc.add(const OtpResendRequested()),
            onSecondary: () => bloc.add(const OtpCancelled()),
          )
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _shaken(
                'code',
                CountryCodePicker(
                  value: _country,
                  focusNode: _codeFocus,
                  hasError: _submitted && _country == null,
                  onChanged: (ct) => setState(() {
                    _country = ct;
                    if (_phone.text.length > (ct.isoCode == 'IN' ? 10 : 15)) _phone.text = _phone.text.substring(0, ct.isoCode == 'IN' ? 10 : 15);
                    _phoneFocus.requestFocus();
                  }),
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: _shaken(
                  'phone',
                  PhoneField(
                    controller: _phone,
                    focusNode: _phoneFocus,
                    country: _country,
                    errorText: _phoneError,
                    showValid: _phoneTouched || _submitted,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _pwFocus.requestFocus(),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: Space.lg),
          FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: _shaken('pw', PasswordField(controller: _password, focusNode: _pwFocus, errorText: _pwError, onSubmitted: (_) => _submit(), onChanged: (_) => setState(() {}))),
          ),
          const SizedBox(height: Space.x2),
          FocusTraversalOrder(order: const NumericFocusOrder(4), child: MgButton(label: otpRequired ? 'Continue' : 'Log in as ${s.role.label}', icon: otpRequired ? Icons.sms_outlined : null, expand: true, loading: submitting, onPressed: _submit)),
          if (otpRequired) ...[
            const SizedBox(height: Space.sm),
            Text('We will text a 6-digit code to this number to confirm it is you.', textAlign: TextAlign.center, style: t.bodySmall),
          ],
          const SizedBox(height: Space.lg),
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (s.role != Role.admin)
              TextButton(onPressed: () => context.go(Routes.signup), child: Text('New to Mine Guardian? Create account', style: t.labelLarge?.copyWith(color: c.amber600))),
            TextButton(onPressed: () => _forgot(context), child: Text('Forgot password?', style: t.labelLarge?.copyWith(color: c.muted))),
          ]),
        ],
      ]),
    );
  }

  void _forgot(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot password?'),
        content: const Text('Ask your supervisor or mine admin to reset your password.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return BlocBuilder<LoginBloc, LoginState>(builder: (context, s) {
      final form = _form(context, s);
      final size = context.sizeClass;
      Widget body;
      if (size == SizeClass.expanded) {
        body = Row(children: [
          const Expanded(flex: 55, child: LoginHero()),
          Expanded(
            flex: 45,
            child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(Space.x3), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Widths.form), child: form))),
          ),
        ]);
      } else if (size == SizeClass.medium) {
        body = Stack(fit: StackFit.expand, children: [
          ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: const LoginHero(showBrand: false)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.x3),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.form),
                child: Container(
                  padding: const EdgeInsets.all(Space.x3),
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.sheet), boxShadow: Shadows.level(3)),
                  child: form,
                ),
              ),
            ),
          ),
        ]);
      } else {
        body = SingleChildScrollView(
          child: Column(children: [
            AspectRatio(aspectRatio: 16 / 7, child: const LoginHero(showBrand: false)),
            Transform.translate(
              offset: const Offset(0, -16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(color: c.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
                child: form,
              ),
            ),
          ]),
        );
      }
      return Scaffold(backgroundColor: c.bg, resizeToAvoidBottomInset: true, body: body);
    });
  }
}
