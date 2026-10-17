import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/tokens.dart';

/// Wraps a card and plays one soft glow pulse whenever [pulseKey] changes (a live update arrived).
/// Nothing animates under reduced motion.
class PulseOnChange extends StatefulWidget {
  const PulseOnChange({super.key, required this.pulseKey, required this.child, this.color, this.radius = Radii.card});
  final Object? pulseKey;
  final Widget child;
  final Color? color;
  final double radius;

  @override
  State<PulseOnChange> createState() => _PulseOnChangeState();
}

class _PulseOnChangeState extends State<PulseOnChange> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.slower * 2);

  @override
  void didUpdateWidget(covariant PulseOnChange old) {
    super.didUpdateWidget(old);
    if (old.pulseKey != widget.pulseKey && widget.pulseKey != null && !Motion.reduce(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? MgColors.of(context).amber500;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.isAnimating ? Curves.easeOut.transform(1 - (_c.value - 0.5).abs() * 2) : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: v == 0 ? const [] : [BoxShadow(color: color.withValues(alpha: 0.45 * v), blurRadius: 18 * v, spreadRadius: 2 * v)],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
