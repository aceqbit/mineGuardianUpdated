import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';

/// The live-map mark drawn in code (CLAUDE.md section 23.4): compass ring, radar sweep and a tunnel glyph, amber on ink.
/// [sweep] 0..1 is the radar angle; [reveal] 0..1 fades the rings in.
class MapLaunchMark extends StatelessWidget {
  const MapLaunchMark({super.key, this.size = 120, this.sweep = 0.25, this.reveal = 1});
  final double size;
  final double sweep;
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkPainter(amber: c.amber500, ink: c.ink900, ring: c.slate300, sweep: sweep, reveal: reveal)));
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.amber, required this.ink, required this.ring, required this.sweep, required this.reveal});
  final Color amber, ink, ring;
  final double sweep, reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final ctr = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(ctr, r, Paint()..color = ink);
    // radar sweep: a fading wedge behind the leading edge
    final a = sweep * 2 * math.pi - math.pi / 2;
    final rect = Rect.fromCircle(center: ctr, radius: r * 0.92);
    canvas.drawArc(
      rect,
      a - 1.1,
      1.1,
      true,
      Paint()
        ..shader = SweepGradient(startAngle: a - 1.1, endAngle: a, colors: [amber.withValues(alpha: 0), amber.withValues(alpha: 0.55)], transform: GradientRotation(0)).createShader(rect),
    );
    canvas.drawLine(ctr, ctr + Offset(math.cos(a), math.sin(a)) * r * 0.92, Paint()
      ..color = amber
      ..strokeWidth = 2);
    // range rings + compass ticks
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = ring.withValues(alpha: 0.35 * reveal);
    for (final f in [0.35, 0.62, 0.9]) {
      canvas.drawCircle(ctr, r * f, ringPaint);
    }
    final tick = Paint()
      ..color = amber.withValues(alpha: reveal)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final ang = i * math.pi / 2 - math.pi / 2;
      final d = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(ctr + d * r * 0.78, ctr + d * r * 0.92, tick);
    }
    // north pointer
    final north = Path()
      ..moveTo(ctr.dx, ctr.dy - r * 0.72)
      ..lineTo(ctr.dx - r * 0.07, ctr.dy - r * 0.56)
      ..lineTo(ctr.dx + r * 0.07, ctr.dy - r * 0.56)
      ..close();
    canvas.drawPath(north, Paint()..color = amber.withValues(alpha: reveal));
    // tunnel glyph: an arch with a trunk line and a junction dot
    final glyph = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round
      ..color = amber;
    final arch = Rect.fromCenter(center: ctr + Offset(0, r * 0.12), width: r * 0.62, height: r * 0.62);
    canvas.drawArc(arch, math.pi, math.pi, false, glyph);
    canvas.drawLine(ctr + Offset(-r * 0.31, r * 0.12), ctr + Offset(-r * 0.31, r * 0.34), glyph);
    canvas.drawLine(ctr + Offset(r * 0.31, r * 0.12), ctr + Offset(r * 0.31, r * 0.34), glyph);
    canvas.drawLine(ctr + Offset(-r * 0.5, r * 0.34), ctr + Offset(r * 0.5, r * 0.34), glyph);
    canvas.drawCircle(ctr + Offset(0, r * 0.12), r * 0.06, Paint()..color = amber);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter o) => o.sweep != sweep || o.reveal != reveal || o.amber != amber;
}

/// Plays the mark once over the map (700 ms sweep, then the mark lifts away), then gets out of the way.
/// Skipped entirely under reduced motion.
class MapLaunchOverlay extends StatefulWidget {
  const MapLaunchOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<MapLaunchOverlay> createState() => _MapLaunchOverlayState();
}

class _MapLaunchOverlayState extends State<MapLaunchOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduce(context)) {
      _done = true;
    } else if (!_c.isAnimating && !_done) {
      _c.forward().whenComplete(() {
        if (mounted) setState(() => _done = true);
      });
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
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (!_done)
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final sweep = (t / 0.7).clamp(0.0, 1.0);
              final out = ((t - 0.7) / 0.3).clamp(0.0, 1.0);
              return ColoredBox(
                color: c.ink900.withValues(alpha: 0.92 * (1 - out)),
                child: Center(
                  child: Opacity(
                    opacity: 1 - out,
                    child: Transform.scale(
                      scale: 1 + 0.6 * Curves.easeIn.transform(out),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        MapLaunchMark(size: 132, sweep: Curves.easeInOut.transform(sweep), reveal: Curves.easeOut.transform(sweep)),
                        const SizedBox(height: Space.lg),
                        Text('LIVE MAP', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.amber500, letterSpacing: 4, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }
}
