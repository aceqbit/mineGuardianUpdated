import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';

/// A button that must be held for [holdFor] before it fires. A progress bar fills while held; releasing early cancels.
class HoldToConfirm extends StatefulWidget {
  const HoldToConfirm({super.key, required this.label, required this.onConfirmed, this.holdFor = const Duration(seconds: 2), this.icon, this.color, this.foreground});
  final String label;
  final VoidCallback onConfirmed;
  final Duration holdFor;
  final IconData? icon;
  final Color? color;
  final Color? foreground;

  @override
  State<HoldToConfirm> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirm> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.holdFor);

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        _c.value = 0;
        widget.onConfirmed();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _release() {
    if (_c.status != AnimationStatus.completed) _c.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final bg = widget.color ?? c.surface;
    final fg = widget.foreground ?? c.text;
    return Semantics(
      button: true,
      label: '${widget.label}. Press and hold for ${widget.holdFor.inSeconds} seconds',
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          HapticFeedback.lightImpact();
          _c.forward(from: 0);
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              decoration: BoxDecoration(color: bg, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(Radii.sm)),
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(
                  child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: Motion.reduce(context) && _c.value > 0 ? 1 : _c.value, child: Container(color: fg.withValues(alpha: 0.18)))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (widget.icon != null) ...[Icon(widget.icon, color: fg, size: 22), const SizedBox(width: Space.sm)],
                    Flexible(child: Text(widget.label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg))),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
