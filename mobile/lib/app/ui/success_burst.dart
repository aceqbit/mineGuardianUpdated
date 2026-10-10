import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/tokens.dart';

/// A drawn check mark inside a circle with a short burst of confetti. Plays once on first build; static (check only)
/// when the user asked for reduced motion. No assets or packages: it is painted.
class SuccessBurst extends StatefulWidget {
  const SuccessBurst({super.key, this.size = 120, this.color, this.confetti = true});
  final double size;
  final Color? color;
  final bool confetti;

  @override
  State<SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<SuccessBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduce(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return Semantics(
      label: 'Success',
      child: SizedBox(
        width: widget.size * 1.6,
        height: widget.size * 1.6,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _BurstPainter(t: _c.value, color: widget.color ?? c.successFill, confetti: widget.confetti && !Motion.reduce(context), palette: [c.amber500, c.successFill, c.info, c.danger]),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.color, required this.confetti, required this.palette});
  final double t;
  final Color color;
  final bool confetti;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final base = size.width / 1.6 / 2;
    // circle pops in over the first 40%
    final pop = Curves.easeOutBack.transform((t / 0.4).clamp(0.0, 1.0));
    canvas.drawCircle(centre, base * pop, Paint()..color = color);
    // check mark draws between 35% and 70%
    final draw = Curves.easeOut.transform(((t - 0.35) / 0.35).clamp(0.0, 1.0));
    if (draw > 0) {
      final p1 = centre + Offset(-base * 0.42, base * 0.02);
      final p2 = centre + Offset(-base * 0.1, base * 0.34);
      final p3 = centre + Offset(base * 0.46, -base * 0.28);
      final path = Path()..moveTo(p1.dx, p1.dy);
      final firstLen = (p2 - p1).distance, secondLen = (p3 - p2).distance;
      final len = (firstLen + secondLen) * draw;
      if (len <= firstLen) {
        final q = p1 + (p2 - p1) * (len / firstLen);
        path.lineTo(q.dx, q.dy);
      } else {
        path.lineTo(p2.dx, p2.dy);
        final q = p2 + (p3 - p2) * ((len - firstLen) / secondLen);
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = base * 0.14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
    if (confetti && t > 0.4) {
      final k = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
      final rnd = math.Random(7); // fixed seed: the same burst every time
      for (var i = 0; i < 22; i++) {
        final angle = rnd.nextDouble() * math.pi * 2;
        final speed = base * (1.1 + rnd.nextDouble() * 0.8);
        final dist = speed * Curves.easeOut.transform(k);
        final drop = base * 0.5 * k * k; // gravity
        final pos = centre + Offset(math.cos(angle) * dist, math.sin(angle) * dist + drop);
        final paint = Paint()..color = palette[i % palette.length].withValues(alpha: (1 - k).clamp(0.0, 1.0));
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(angle + k * 6);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 8, height: 4), const Radius.circular(1)), paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color || old.confetti != confetti;
}
