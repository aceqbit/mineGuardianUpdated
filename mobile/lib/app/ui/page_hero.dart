import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../contracts/enums.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'role_accent.dart';

/// Page hero for the add-on screens (CLAUDE.md section 23.2 / 23.7): deep navy with a role-tinted glow that drifts slowly
/// (8 s loop) behind the title. Static under reduced motion.
class PageHero extends StatefulWidget {
  const PageHero({super.key, required this.role, required this.title, this.subtitle, this.trailing, this.bottom, this.icon});
  final Role role;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? bottom;
  final IconData? icon;

  @override
  State<PageHero> createState() => _PageHeroState();
}

class _PageHeroState extends State<PageHero> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduce(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final accent = RoleAccent.of(context, widget.role);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sheet),
      child: AnimatedBuilder(
        animation: _drift,
        builder: (context, child) {
          final a = _drift.value * 2 * math.pi;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6 + 0.5 * math.cos(a), -0.8 + 0.4 * math.sin(a)),
                radius: 1.3,
                colors: [accent.fill.withValues(alpha: 0.55), c.ink800, c.ink900],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: child,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(Space.x2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(Space.sm),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.sm), border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
                  child: Icon(widget.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: Space.md),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: Space.xs),
                    Text(widget.subtitle!, style: t.bodyMedium?.copyWith(color: c.slate300), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ]),
              ),
              if (widget.trailing != null) ...[const SizedBox(width: Space.md), widget.trailing!],
            ]),
            if (widget.bottom != null) ...[const SizedBox(height: Space.lg), widget.bottom!],
          ]),
        ),
      ),
    );
  }
}
