import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/tokens.dart';

/// Circular gauge that animates from 0 to [value] / [max]. A null [value] shows a neutral "—" ring
/// (numbers are never invented when the data is not available yet).
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.value, this.max = 1000, this.size = 112, this.label, this.color, this.onDark = false, this.center});
  final num? value;
  final num max;
  final double size;
  final String? label;
  final Color? color;
  final bool onDark;

  /// Replaces the number in the middle (e.g. an icon).
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final frac = value == null ? 0.0 : (value! / max).clamp(0.0, 1.0).toDouble();
    final track = onDark ? Colors.white.withValues(alpha: 0.18) : c.border;
    final arc = color ?? (onDark ? c.amber500 : c.amberText);
    final fg = onDark ? Colors.white : c.text;
    return Semantics(
      label: '${label ?? 'Score'} ${value == null ? 'not available' : '${value!.round()} of ${max.round()}'}',
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: frac),
          duration: Motion.of(context, const Duration(milliseconds: 900)),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(fraction: v, track: track, arc: arc, stroke: size * 0.1),
            child: Center(
              child: center ??
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(value == null ? '—' : '${(v * max).round()}', style: t.headlineMedium?.copyWith(color: fg, fontSize: size * 0.28, height: 1.1)),
                    if (label != null) Text(label!, style: t.labelSmall?.copyWith(color: onDark ? Colors.white70 : c.muted)),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.track, required this.arc, required this.stroke});
  final double fraction;
  final Color track;
  final Color arc;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = Rect.fromCircle(center: rect.center, radius: (math.min(size.width, size.height) - stroke) / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    if (fraction > 0) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = arc;
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * fraction, false, p);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.track != track || old.arc != arc || old.stroke != stroke;
}
