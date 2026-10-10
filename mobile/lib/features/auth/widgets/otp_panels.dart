import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_text_field.dart';
import '../../../core/auth/demo_otp_service.dart';

/// "1 Number & password  ->  2 Verify code" progress, so users know a code is part of logging in.
class OtpStepper extends StatelessWidget {
  const OtpStepper({super.key, required this.step, this.labels = const ['Number & password', 'Verify code']});

  /// 0 or 1.
  final int step;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    Widget dot(int i) {
      final done = i < step, active = i == step;
      return AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: done || active ? c.amber500 : c.slate200, border: Border.all(color: active ? c.amberText : Colors.transparent, width: 2)),
        child: done ? Icon(Icons.check, size: 16, color: c.ink900) : Text('${i + 1}', style: t.labelMedium?.copyWith(color: active ? c.ink900 : c.slate500)),
      );
    }

    return Semantics(
      label: 'Step ${step + 1} of ${labels.length}: ${labels[step]}',
      child: Row(children: [
        dot(0),
        const SizedBox(width: Space.sm),
        Flexible(child: Text(labels[0], maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(color: step == 0 ? c.text : c.muted))),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: Space.sm), child: AnimatedContainer(duration: Motion.of(context, Motion.base), height: 2, color: step > 0 ? c.amber500 : c.slate200))),
        dot(1),
        const SizedBox(width: Space.sm),
        Flexible(child: Text(labels[1], maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(color: step == 1 ? c.text : c.muted))),
      ]),
    );
  }
}

/// 6-digit code entry with a resend countdown. The code lives only in this widget's controller (never in bloc state,
/// never autofilled) and the countdown is driven by an AnimationController.
class OtpCodeEntry extends StatefulWidget {
  const OtpCodeEntry({
    super.key,
    required this.maskedPhone,
    required this.cooldownUntil,
    required this.busy,
    required this.onVerify,
    required this.onResend,
    required this.onSecondary,
    required this.secondaryLabel,
    this.title = 'Enter the 6-digit code',
  });
  final String? maskedPhone;
  final DateTime? cooldownUntil;
  final bool busy;
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
    if (old.cooldownUntil != widget.cooldownUntil) {
      _syncCooldown();
      _code.clear(); // a fresh code was sent
    }
  }

  void _syncCooldown() {
    final until = widget.cooldownUntil;
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      ValueListenableBuilder<String?>(
        valueListenable: DemoOtp.code,
        builder: (context, demo, _) => demo == null
            ? const SizedBox.shrink()
            : Container(
                margin: const EdgeInsets.only(bottom: Space.lg),
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(color: c.amber50, border: Border.all(color: c.amber500), borderRadius: BorderRadius.circular(Radii.sm)),
                child: Row(children: [
                  Icon(Icons.science_outlined, color: c.amberText),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text('DEMO MODE: no SMS was sent. Your code is $demo', style: t.titleSmall?.copyWith(color: c.text))),
                ]),
              ),
      ),
      Text(widget.title, style: t.titleMedium),
      const SizedBox(height: Space.xs),
      Text('We sent a code by SMS to ${widget.maskedPhone ?? 'your phone'}. It works once and expires in a few minutes.', style: t.bodySmall),
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
      MgButton(label: 'Verify and continue', expand: true, loading: widget.busy, onPressed: _code.text.length == 6 ? () => widget.onVerify(_code.text) : null),
      const SizedBox(height: Space.sm),
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AnimatedBuilder(
          animation: _cooldown,
          builder: (context, _) {
            final secs = _secondsLeft;
            return TextButton(
              onPressed: secs > 0 || widget.busy ? null : widget.onResend,
              child: Text(secs > 0 ? 'Resend code in ${secs}s' : 'Resend code', style: t.labelLarge?.copyWith(color: secs > 0 ? c.muted : c.amberText)),
            );
          },
        ),
        TextButton(onPressed: widget.busy ? null : widget.onSecondary, child: Text(widget.secondaryLabel, style: t.labelLarge?.copyWith(color: c.muted))),
      ]),
    ]);
  }
}
