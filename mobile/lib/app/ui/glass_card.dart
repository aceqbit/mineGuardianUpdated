import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/tokens.dart';

/// Frosted glass panel (add-on kit, CLAUDE.md section 23.2 / 23.7): surface at 72% opacity, hairline border, a sheen
/// from the top-left and, when it sits on something worth blurring (a hero, a map), a σ 12 backdrop blur.
/// Pressing scales to 0.97; everything static under reduced motion.
class GlassCard extends StatefulWidget {
  const GlassCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(Space.lg), this.blur = false, this.radius = Radii.card, this.accent, this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Backdrop blur. Only worth its cost over imagery (hero, map); plain page backgrounds look the same without it.
  final bool blur;
  final double radius;

  /// Optional accent drawn as a 3 px top edge (role colour, status colour).
  final Color? accent;
  final String? semanticLabel;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(widget.radius);
    final sheen = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Colors.white.withValues(alpha: dark ? 0.07 : 0.55), Colors.white.withValues(alpha: 0)],
      stops: const [0, 0.55],
    );
    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.72),
        borderRadius: r,
        border: Border.all(color: c.border.withValues(alpha: dark ? 0.9 : 1)),
        boxShadow: Shadows.level(_down ? 1 : 2, dark: dark),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: r, gradient: sheen),
        child: Stack(children: [
          if (widget.accent != null) Positioned(left: 0, right: 0, top: 0, height: 3, child: ColoredBox(color: widget.accent!)),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: r,
              onTap: widget.onTap,
              onHighlightChanged: widget.onTap == null ? null : (v) => setState(() => _down = v),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ]),
      ),
    );
    panel = ClipRRect(borderRadius: r, child: widget.blur ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: panel) : panel);
    final scaled = AnimatedScale(scale: _down && !Motion.reduce(context) ? Motion.pressScale : 1, duration: Motion.of(context, Motion.fast), child: panel);
    return widget.semanticLabel == null ? scaled : Semantics(label: widget.semanticLabel, button: widget.onTap != null, child: scaled);
  }
}
