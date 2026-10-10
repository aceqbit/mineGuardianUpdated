import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/mg_segmented.dart';
import '../../../app/ui/mg_text_field.dart';
import '../../../app/ui/section_header.dart';
import '../../../app/ui/toast.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/push/push_registrar.dart';
import '../bloc/signup_bloc.dart';
import '../bloc/signup_event.dart';
import '../bloc/signup_state.dart';
import '../data/countries.dart';
import '../data/password_rules.dart';
import '../data/phone_validator.dart';
import '../data/signup_repository.dart';
import '../widgets/country_code_picker.dart';
import '../widgets/date_field.dart';
import '../widgets/dropdown_field.dart';
import '../widgets/password_field.dart';
import '../widgets/phone_field.dart';
import '../widgets/otp_panels.dart';
import '../widgets/step_header.dart';

const designations = ['Miner', 'Shot-firer', 'Mining Sirdar', 'Overman', 'Electrician', 'Fitter', 'Surveyor', 'Pump Operator', 'Supervisor', 'Other'];
const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
const relations = ['Spouse', 'Parent', 'Sibling', 'Child', 'Friend', 'Other'];

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => SignupBloc(repo: SignupRepository(auth: ctx.read<AuthRepository>(), api: ctx.read<ApiClient>()))..add(const SignupStarted()),
        child: const _SignupView(),
      );
}

class _SignupView extends StatefulWidget {
  const _SignupView();

  @override
  State<_SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends State<_SignupView> {
  final _name = TextEditingController();
  final _empId = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _emName = TextEditingController();
  final _emPhone = TextEditingController();
  final _address = TextEditingController();
  final _phoneFocus = FocusNode();
  final _pwFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _emPhoneFocus = FocusNode();
  Country? _country;
  Country? _emCountry;
  final _attempted = <int>{};

  @override
  void dispose() {
    for (final c in [_name, _empId, _phone, _password, _confirm, _emName, _emPhone, _address]) {
      c.dispose();
    }
    for (final f in [_phoneFocus, _pwFocus, _confirmFocus, _emPhoneFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  // ---- validation ----
  String? _nameErr() {
    final v = _name.text.trim();
    if (v.length < 2 || v.length > 60) return 'Enter your full name (2 to 60 characters)';
    if (!RegExp(r"^[\p{L} .'-]+$", unicode: true).hasMatch(v)) return "Letters, spaces and . ' - only";
    return null;
  }

  String? _empErr() => RegExp(r'^[A-Za-z]{2,4}-?\d{3,8}$').hasMatch(_empId.text.trim()) ? null : 'Use a format like MIN-0123';

  String? _confirmErr() => _confirm.text == _password.text && _confirm.text.isNotEmpty ? null : 'Passwords do not match';

  String? _emNameErr() {
    final v = _emName.text.trim();
    return v.length >= 2 && v.length <= 60 ? null : 'Enter the contact name';
  }

  String? _emPhoneErr() {
    final v = validatePhone(_emCountry?.isoCode, _emPhone.text);
    if (v.error != null) return v.error;
    final own = validatePhone(_country?.isoCode, _phone.text);
    if (own.isValid && own.e164 == v.e164) return "Emergency number must differ from your own";
    return null;
  }

  int _age(DateTime d) {
    final n = DateTime.now();
    var a = n.year - d.year;
    if (n.month < d.month || (n.month == d.month && n.day < d.day)) a--;
    return a;
  }

  String? _dobErr(SignupState s) {
    if (s.dob == null) return 'Select your date of birth';
    final a = _age(s.dob!);
    return a >= 18 && a <= 65 ? null : 'Age must be between 18 and 65';
  }

  Map<String, String?> _errors(int step, SignupState s) {
    switch (step) {
      case 0:
        return {
          'name': _nameErr(),
          'emp': _empErr(),
          'phone': validatePhone(_country?.isoCode, _phone.text).error,
          'pw': PasswordRules.evaluate(_password.text).firstError,
          'confirm': _confirmErr(),
        };
      case 1:
        return {
          'mine': s.mineName == null ? 'Select your mine' : null,
          'zone': s.zoneId == null ? 'Select your zone' : null,
          'shift': s.shift == null ? 'Select your shift' : null,
          'designation': s.designation == null ? 'Select a designation' : null,
          'doj': s.dateOfJoining == null ? 'Select date of joining' : null,
        };
      default:
        return {
          'dob': _dobErr(s),
          'blood': s.bloodGroup == null ? 'Select blood group' : null,
          'emName': _emNameErr(),
          'relation': s.relation == null ? 'Select a relation' : null,
          'emPhone': _emPhoneErr(),
          'address': _address.text.trim().length > 200 ? 'At most 200 characters' : null,
          'consent': s.consent ? null : 'Please confirm your details',
        };
    }
  }

  bool _stepValid(int step, SignupState s) => _errors(step, s).values.every((e) => e == null);

  String? _err(int step, String key, SignupState s) => _attempted.contains(step) ? _errors(step, s)[key] : null;

  void _next(SignupState s) {
    setState(() => _attempted.add(s.step));
    if (!_stepValid(s.step, s)) return;
    context.read<SignupBloc>().add(SignupStepChanged(s.step + 1));
  }

  void _submit(SignupState s) {
    setState(() => _attempted.add(2));
    for (var i = 0; i < 3; i++) {
      if (!_stepValid(i, s)) {
        setState(() => _attempted.add(i));
        context.read<SignupBloc>().add(SignupStepChanged(i));
        return;
      }
    }
    final own = validatePhone(_country!.isoCode, _phone.text);
    final em = validatePhone(_emCountry!.isoCode, _emPhone.text);
    context.read<SignupBloc>().add(SignupSubmitted(SignupData(
          role: s.role,
          fullName: _name.text,
          employeeId: _empId.text.trim().toUpperCase(),
          isoCode: _country!.isoCode,
          dialCode: _country!.dialCode,
          national: own.national!,
          e164: own.e164!,
          password: _password.text,
          mineName: s.mineName!,
          zoneId: s.zoneId!,
          shift: s.shift!,
          designation: s.designation!,
          experienceYears: s.experienceYears,
          dateOfJoining: s.dateOfJoining!,
          dob: s.dob!,
          bloodGroup: s.bloodGroup!,
          emergencyName: _emName.text,
          emergencyRelation: s.relation!,
          emergencyIso: _emCountry!.isoCode,
          emergencyDial: _emCountry!.dialCode,
          emergencyNational: em.national!,
          address: _address.text,
        )));
  }

  // ---- steps ----
  Widget _step0(SignupState s) {
    final bloc = context.read<SignupBloc>();
    return Column(key: const ValueKey(0), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader(title: 'Create your account', subtitle: 'Step 1 of 3 · Account'),
      MgSegmented<String>(
        value: s.role,
        onChanged: (r) => bloc.add(SignupFieldsChanged(role: r)),
        segments: const [MgSegment(value: 'miner', label: 'Miner', icon: Icons.engineering), MgSegment(value: 'supervisor', label: 'Supervisor', icon: Icons.badge)],
      ),
      const SizedBox(height: Space.lg),
      MgTextField(controller: _name, label: 'Full name', errorText: _err(0, 'name', s), textInputAction: TextInputAction.next, textCapitalization: TextCapitalization.words, maxLength: 60, onChanged: (_) => setState(() {})),
      const SizedBox(height: Space.lg),
      MgTextField(
        controller: _empId,
        label: 'Employee ID',
        hint: 'e.g. MIN-0123',
        errorText: _err(0, 'emp', s),
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')), _UpperCaseFormatter()],
        maxLength: 14,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Space.lg),
      _phoneRow(country: _country, onCountry: (c) => setState(() => _country = c), controller: _phone, focus: _phoneFocus, error: _err(0, 'phone', s), label: 'Mobile number'),
      const SizedBox(height: Space.lg),
      PasswordField(controller: _password, focusNode: _pwFocus, errorText: _err(0, 'pw', s), textInputAction: TextInputAction.next, onChanged: (_) => setState(() {}), onSubmitted: (_) => _confirmFocus.requestFocus()),
      const SizedBox(height: Space.lg),
      PasswordField(controller: _confirm, focusNode: _confirmFocus, label: 'Confirm password', showRules: false, errorText: _err(0, 'confirm', s), onChanged: (_) => setState(() {})),
    ]);
  }

  Widget _phoneRow({required Country? country, required ValueChanged<Country> onCountry, required TextEditingController controller, required FocusNode focus, required String? error, required String label}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CountryCodePicker(value: country, hasError: error != null && country == null, onChanged: (c) {
        onCountry(c);
        focus.requestFocus();
      }),
      const SizedBox(width: Space.md),
      Expanded(child: PhoneField(controller: controller, focusNode: focus, country: country, errorText: error, showValid: true, label: label, onChanged: (_) => setState(() {}))),
    ]);
  }

  Widget _step1(SignupState s) {
    final bloc = context.read<SignupBloc>();
    final now = DateTime.now();
    return Column(key: const ValueKey(1), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader(title: 'Where do you work?', subtitle: 'Step 2 of 3 · Work'),
      DropdownField<String>(label: 'Mine', value: s.mineName, items: s.mines, errorText: _err(1, 'mine', s), onChanged: (v) => bloc.add(SignupFieldsChanged(mineName: v))),
      const SizedBox(height: Space.lg),
      DropdownField<String>(
        label: 'Zone',
        value: s.zoneId,
        items: s.zonesOfMine.map((z) => z.id).toList(),
        itemLabel: (id) => s.zones.firstWhere((z) => z.id == id).name,
        enabled: s.mineName != null,
        errorText: _err(1, 'zone', s),
        onChanged: (v) => bloc.add(SignupFieldsChanged(zoneId: v)),
      ),
      const SizedBox(height: Space.lg),
      Text('Shift', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: Space.sm),
      MgSegmented<String>(
        value: s.shift ?? '',
        onChanged: (v) => bloc.add(SignupFieldsChanged(shift: v)),
        segments: [for (final sh in Shift.values) MgSegment(value: sh.wire, label: '${sh.wire} · ${sh.window}')],
      ),
      if (_err(1, 'shift', s) != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(_err(1, 'shift', s)!, style: TextStyle(color: MgColors.of(context).danger, fontSize: 12))),
      const SizedBox(height: Space.lg),
      DropdownField<String>(label: 'Designation', value: s.designation, items: designations, errorText: _err(1, 'designation', s), onChanged: (v) => bloc.add(SignupFieldsChanged(designation: v))),
      const SizedBox(height: Space.lg),
      _Stepper(label: 'Years of experience', value: s.experienceYears, min: 0, max: 45, onChanged: (v) => bloc.add(SignupFieldsChanged(experienceYears: v))),
      const SizedBox(height: Space.lg),
      DateField(label: 'Date of joining', value: s.dateOfJoining, firstDate: DateTime(1980), lastDate: now, errorText: _err(1, 'doj', s), onChanged: (d) => bloc.add(SignupFieldsChanged(dateOfJoining: d))),
    ]);
  }

  Widget _step2(SignupState s) {
    final bloc = context.read<SignupBloc>();
    final c = MgColors.of(context);
    final now = DateTime.now();
    return Column(key: const ValueKey(2), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader(title: 'About you', subtitle: 'Step 3 of 3 · Personal and emergency'),
      DateField(
        label: 'Date of birth',
        value: s.dob,
        firstDate: DateTime(now.year - 65, now.month, now.day).subtract(const Duration(days: 1)),
        lastDate: DateTime(now.year - 18, now.month, now.day),
        initialPickerDate: DateTime(now.year - 30, 1, 1),
        errorText: _err(2, 'dob', s),
        onChanged: (d) => bloc.add(SignupFieldsChanged(dob: d)),
      ),
      const SizedBox(height: Space.lg),
      Text('Blood group', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: Space.sm),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        for (final b in bloodGroups) ChoiceChip(label: Text(b), selected: s.bloodGroup == b, showCheckmark: false, onSelected: (_) => bloc.add(SignupFieldsChanged(bloodGroup: b))),
      ]),
      if (_err(2, 'blood', s) != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(_err(2, 'blood', s)!, style: TextStyle(color: c.danger, fontSize: 12))),
      const SizedBox(height: Space.x2),
      Text('Emergency contact', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Space.md),
      MgTextField(controller: _emName, label: 'Contact name', errorText: _err(2, 'emName', s), textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next, maxLength: 60, onChanged: (_) => setState(() {})),
      const SizedBox(height: Space.lg),
      DropdownField<String>(label: 'Relation', value: s.relation, items: relations, errorText: _err(2, 'relation', s), onChanged: (v) => bloc.add(SignupFieldsChanged(relation: v))),
      const SizedBox(height: Space.lg),
      _phoneRow(country: _emCountry, onCountry: (c) => setState(() => _emCountry = c), controller: _emPhone, focus: _emPhoneFocus, error: _err(2, 'emPhone', s), label: 'Contact mobile'),
      const SizedBox(height: Space.lg),
      MgTextField(controller: _address, label: 'Address (optional)', maxLines: 3, maxLength: 200, errorText: _err(2, 'address', s), onChanged: (_) => setState(() {})),
      const SizedBox(height: Space.lg),
      _review(s),
      const SizedBox(height: Space.md),
      Row(children: [
        Switch(value: s.consent, onChanged: (v) => bloc.add(SignupFieldsChanged(consent: v))),
        const SizedBox(width: Space.sm),
        Expanded(child: Text('I confirm these details are correct', style: Theme.of(context).textTheme.bodyMedium)),
      ]),
      if (_err(2, 'consent', s) != null) Text(_err(2, 'consent', s)!, style: TextStyle(color: c.danger, fontSize: 12)),
    ]);
  }

  String _masked(Country? c, String national) => national.length < 4 || c == null ? '' : '+${c.dialCode} ${'*' * (national.length - 4)}${national.substring(national.length - 4)}';

  Widget _review(SignupState s) {
    final t = Theme.of(context).textTheme;
    Widget row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 110, child: Text(k, style: t.bodySmall)), Expanded(child: Text(v.isEmpty ? '—' : v, style: t.bodyMedium))]));
    final zone = s.zones.where((z) => z.id == s.zoneId).firstOrNull;
    return MgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Review', style: t.titleMedium),
        const SizedBox(height: Space.sm),
        row('Name', _name.text.trim()),
        row('Employee ID', _empId.text.trim().toUpperCase()),
        row('Mobile', _masked(_country, _phone.text)),
        row('Role', s.role == 'miner' ? 'Miner' : 'Supervisor'),
        row('Zone', zone?.name ?? ''),
        row('Shift', s.shift ?? ''),
        row('Emergency', '${_emName.text.trim()} · ${_masked(_emCountry, _emPhone.text)}'),
      ]),
    );
  }

  Widget _errorBanner(SignupState s) {
    final c = MgColors.of(context);
    if (s.errorMessage == null || s.status != SignupStatus.failure || s.errorStep != s.step) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: c.dangerBg, borderRadius: BorderRadius.circular(Radii.sm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.errorMessage!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.danger)),
        if (s.alreadyRegistered) TextButton(onPressed: () => context.go(Routes.login), child: const Text('Go to login')),
      ]),
    );
  }

  Widget _verifyPanel(BuildContext context, SignupState s) {
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    final bloc = context.read<SignupBloc>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.form),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Verify your phone', style: t.headlineMedium),
              const SizedBox(height: Space.xs),
              Text('Your account is created once the number is confirmed', style: t.bodySmall),
              const SizedBox(height: Space.lg),
              const OtpStepper(step: 1, labels: ['Your details', 'Verify code']),
              const SizedBox(height: Space.x2),
              if (s.errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: Space.lg),
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(color: c.dangerBg, borderRadius: BorderRadius.circular(Radii.sm)),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: c.danger, size: 20),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(s.errorMessage!, style: t.bodyMedium?.copyWith(color: c.danger))),
                  ]),
                ),
              OtpCodeEntry(
                maskedPhone: s.otpMasked,
                cooldownUntil: s.otpCooldownUntil,
                busy: s.status == SignupStatus.submitting,
                secondaryLabel: 'Cancel sign-up',
                onVerify: (code) => bloc.add(SignupOtpSubmitted(code)),
                onResend: () => bloc.add(const SignupOtpResendRequested()),
                onSecondary: () => bloc.add(const SignupOtpCancelled()),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return BlocConsumer<SignupBloc, SignupState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == SignupStatus.success && s.user != null) {
          Toast.show(context, 'Welcome, ${s.user!.firstName}', kind: ToastKind.success);
          context.read<SessionBloc>().add(LoggedIn(s.user!));
          PushRegistrar(api: context.read<ApiClient>()).register();
        }
      },
      builder: (context, s) {
        final expanded = context.isExpanded;
        final submitting = s.status == SignupStatus.submitting;
        final Widget content;
        final verifyingPhone = s.otpMasked != null && (s.status == SignupStatus.verifying || s.status == SignupStatus.submitting);
        if (verifyingPhone) {
          content = _verifyPanel(context, s);
        } else if (s.status == SignupStatus.loadingZones) {
          content = const Center(child: CircularProgressIndicator());
        } else if (s.status == SignupStatus.zonesFailed) {
          content = EmptyState(icon: Icons.cloud_off, title: 'Could not load zones', message: 'Check your connection and try again', actionLabel: 'Retry', onAction: () => context.read<SignupBloc>().add(const SignupStarted()));
        } else {
          content = SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (!expanded) ...[StepHeader(step: s.step, onTap: (i) => context.read<SignupBloc>().add(SignupStepChanged(i))), const SizedBox(height: Space.x2)],
                    _errorBanner(s),
                    PageTransitionSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder: (child, a, sa) => SharedAxisTransition(animation: a, secondaryAnimation: sa, transitionType: SharedAxisTransitionType.horizontal, fillColor: Colors.transparent, child: child),
                      child: [_step0, _step1, _step2][s.step](s),
                    ),
                    const SizedBox(height: Space.x2),
                    Row(children: [
                      if (s.step > 0) Expanded(child: MgButton(label: 'Back', kind: MgButtonKind.secondary, onPressed: submitting ? null : () => context.read<SignupBloc>().add(SignupStepChanged(s.step - 1)))),
                      if (s.step > 0) const SizedBox(width: Space.md),
                      Expanded(
                        flex: 2,
                        child: s.step < 2
                            ? MgButton(label: 'Continue', onPressed: () => _next(s))
                            : MgButton(label: submitting ? (s.progressLabel ?? 'Creating account…') : 'Create account', loading: submitting, onPressed: () => _submit(s)),
                      ),
                    ]),
                    const SizedBox(height: Space.lg),
                    Center(child: TextButton(onPressed: () => context.go(Routes.login), child: const Text('Already have an account? Log in'))),
                  ]),
                ),
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: c.bg,
          appBar: expanded ? null : AppBar(title: const Text('Sign up')),
          body: expanded
              ? Row(children: [
                  Container(
                    width: 280,
                    color: c.ink900,
                    padding: const EdgeInsets.all(Space.x3),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.shield, color: c.amber500, size: 36),
                      const SizedBox(height: Space.md),
                      Text('Mine Guardian', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
                      const SizedBox(height: Space.x3),
                      Theme(data: Theme.of(context).copyWith(textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white)), child: StepHeader(step: s.step, vertical: true, onTap: (i) => context.read<SignupBloc>().add(SignupStepChanged(i)))),
                    ]),
                  ),
                  Expanded(child: content),
                ])
              : content,
        );
      },
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      Expanded(child: Text(label, style: t.bodyLarge)),
      IconButton.outlined(tooltip: 'Decrease', onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove)),
      SizedBox(width: 48, child: Text('$value', textAlign: TextAlign.center, style: t.titleMedium)),
      IconButton.outlined(tooltip: 'Increase', onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add)),
    ]);
  }
}
