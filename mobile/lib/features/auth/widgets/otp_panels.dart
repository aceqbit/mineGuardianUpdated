import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_text_field.dart';
import '../bloc/login_state.dart';

/// 6-digit code entry with a resend countdown. The code lives only in this widget's controller (never in bloc state,
/// never autofilled) and the countdown is driven by an AnimationController.
class OtpCodeEntry extends StatefulWidget {
  const OtpCodeEntry({super.key, required this.state, required this.onVerify, required this.onResend, required this.onSecondary, required this.secondaryLabel, this.title = 'Enter the 6-digit code'});
  final LoginState state;
  final ValueChanged<String> onVerify;
  final VoidCallback onResend;
  final VoidCallback onSecondary;
  final String secondaryLabel;
  final String title;

  @override
  State<OtpCodeEntry> createState() => _OtpCodeEntryState();
}

class _OtpCodeEntryState extends State<OtpCodeEntry> with SingleTickerProviderStateMixin {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _cooldown = AnimationController(vsync: this);
  DateTime? _until;

  @override
  void initState() {
    super.initState();
    _syncCooldown();
  }

  @override
  void didUpdateWidget(OtpCodeEntry old) {
    super.didUpdateWidget(old);
    if (old.state.cooldownUntil != widget.state.cooldownUntil) _syncCooldown();
    if (old.state.otp != widget.state.otp) _code.clear();
  }

  void _syncCooldown() {
    final until = widget.state.cooldownUntil;
    _until = until;
    final left = until == null ? Duration.zero : until.difference(DateTime.now());
    if (left <= Duration.zero) {
      _cooldown.value = 1;
      return;
    }
    _cooldown.duration = left;
    _cooldown.forward(from: 0);
  }

  int get _secondsLeft {
    final u = _until;
    if (u == null) return 0;
    final s = u.difference(DateTime.now()).inSeconds + 1;
    return s < 0 ? 0 : s;
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    final s = widget.state;
    final busy = s.status == LoginStatus.submitting;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(widget.title, style: t.titleMedium),
      const SizedBox(height: Space.xs),
      Text('We sent a code by SMS to ${s.maskedPhone ?? 'your phone'}. It works once and expires in a few minutes.', style: t.bodySmall),
      const SizedBox(height: Space.lg),
      MgTextField(
        controller: _code,
        focusNode: _focus,
        label: '6-digit code',
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) => widget.onVerify(v),
      ),
      const SizedBox(height: Space.lg),
      MgButton(label: 'Verify code', expand: true, loading: busy, onPressed: _code.text.length == 6 ? () => widget.onVerify(_code.text) : null),
      const SizedBox(height: Space.sm),
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AnimatedBuilder(
          animation: _cooldown,
          builder: (context, _) {
            final secs = _secondsLeft;
            return TextButton(
              onPressed: secs > 0 || busy ? null : widget.onResend,
              child: Text(secs > 0 ? 'Resend code in ${secs}s' : 'Resend code', style: t.labelLarge?.copyWith(color: secs > 0 ? c.muted : c.amber600)),
            );
          },
        ),
        TextButton(onPressed: busy ? null : widget.onSecondary, child: Text(widget.secondaryLabel, style: t.labelLarge?.copyWith(color: c.muted))),
      ]),
    ]);
  }
}

/// Shown after a successful password login when the phone is not yet linked for OTP.
class OtpLinkOffer extends StatelessWidget {
  const OtpLinkOffer({super.key, required this.state, required this.onAccept, required this.onSkip});
  final LoginState state;
  final VoidCallback onAccept;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    final busy = state.status == LoginStatus.submitting;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(color: c.infoBg, borderRadius: BorderRadius.circular(Radii.card)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.sms_outlined, color: c.info),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Enable OTP login?', style: t.titleMedium?.copyWith(color: c.info)),
              const SizedBox(height: Space.xs),
              Text('Verify ${state.maskedPhone ?? 'this phone'} with an SMS code once. Next time you can log in with a code instead of your password.', style: t.bodyMedium),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: Space.lg),
      MgButton(label: 'Send code', icon: Icons.send, expand: true, loading: busy, onPressed: onAccept),
      const SizedBox(height: Space.sm),
      TextButton(onPressed: busy ? null : onSkip, child: Text('Not now', style: t.labelLarge?.copyWith(color: c.muted))),
    ]);
  }
}
