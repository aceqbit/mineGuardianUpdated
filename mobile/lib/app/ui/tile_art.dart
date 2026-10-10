import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_images.dart';
import '../theme/tokens.dart';

/// Illustrations drawn in code for every image tile. They are the picture when the network photo is slow, blocked or
/// offline (the photo fades in on top when it loads), so a tile is never an empty dark box. No asset files.
enum TileArtKind { capture, hazard, sos, leaderboard, rewards, supervisorFeed, zones, crisis, reports, broadcast, contacts, hero }

/// Which illustration belongs to an [AppImages] URL.
TileArtKind tileArtFor(String imageUrl) {
  final name = AppImages.all.entries.where((e) => e.value == imageUrl).map((e) => e.key).firstOrNull;
  return switch (name) {
    'capture' => TileArtKind.capture,
    'hazard' => TileArtKind.hazard,
    'sos' => TileArtKind.sos,
    'leaderboard' => TileArtKind.leaderboard,
    'rewards' => TileArtKind.rewards,
    'supervisorFeed' => TileArtKind.supervisorFeed,
    'adminZones' => TileArtKind.zones,
    'adminCrisis' => TileArtKind.crisis,
    'adminReports' => TileArtKind.reports,
    'broadcast' => TileArtKind.broadcast,
    'contacts' => TileArtKind.contacts,
    _ => TileArtKind.hero,
  };
}

class TileArt extends StatelessWidget {
  const TileArt({super.key, required this.kind});
  final TileArtKind kind;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return ExcludeSemantics(child: CustomPaint(painter: _ArtPainter(kind, c), size: Size.infinite));
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.kind, this.c);
  final TileArtKind kind;
  final MgColors c;

  (Color, Color) get _bg => switch (kind) {
        TileArtKind.capture => (c.infoFill, c.ink800),
        TileArtKind.hazard => (c.warningFill, c.ink800),
        TileArtKind.sos => (c.dangerFill, c.crisis),
        TileArtKind.leaderboard => (c.ink600, c.ink900),
        TileArtKind.rewards => (c.medalGold, c.ink800),
        TileArtKind.supervisorFeed => (c.ink600, c.ink800),
        TileArtKind.zones => (c.successFill, c.ink800),
        TileArtKind.crisis => (c.crisis, c.ink900),
        TileArtKind.reports => (c.ink600, c.infoFill),
        TileArtKind.broadcast => (c.warningFill, c.crisis),
        TileArtKind.contacts => (c.infoFill, c.ink900),
        TileArtKind.hero => (c.ink700, c.ink900),
      };

  @override
  void paint(Canvas canvas, Size s) {
    final (a, b) = _bg;
    canvas.drawRect(Offset.zero & s, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]).createShader(Offset.zero & s));
    final white = Paint()..color = Colors.white.withValues(alpha: 0.36);
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.13);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final w = s.width, h = s.height;
    // faint rings that every tile shares: depth without noise
    canvas.drawCircle(Offset(w * 0.85, h * 0.12), w * 0.32, soft);
    canvas.drawCircle(Offset(w * 0.1, h * 0.95), w * 0.4, soft);

    switch (kind) {
      case TileArtKind.capture:
        final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.5, h * 0.42), width: w * 0.5, height: h * 0.3), const Radius.circular(14));
        canvas.drawRRect(body, white);
        canvas.drawCircle(Offset(w * 0.5, h * 0.42), h * 0.1, line);
        canvas.drawCircle(Offset(w * 0.5, h * 0.42), h * 0.045, white);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.4, h * 0.24, w * 0.14, h * 0.05), const Radius.circular(6)), white);
        _hardHat(canvas, Offset(w * 0.2, h * 0.3), w * 0.09, white);
      case TileArtKind.hazard:
        final tri = Path()
          ..moveTo(w * 0.5, h * 0.14)
          ..lineTo(w * 0.72, h * 0.54)
          ..lineTo(w * 0.28, h * 0.54)
          ..close();
        canvas.drawPath(tri, white);
        canvas.drawPath(tri, line);
        canvas.drawLine(Offset(w * 0.5, h * 0.27), Offset(w * 0.5, h * 0.4), line..strokeWidth = 5);
        canvas.drawCircle(Offset(w * 0.5, h * 0.47), 3.5, Paint()..color = Colors.white.withValues(alpha: 0.6));
        line.strokeWidth = 3;
        for (var i = -2; i < 12; i++) {
          final x = i * w * 0.12;
          canvas.drawLine(Offset(x, h * 0.6), Offset(x + w * 0.1, h * 0.52), line..strokeWidth = 7);
        }
        line.strokeWidth = 3;
      case TileArtKind.sos:
        final ctr = Offset(w * 0.5, h * 0.4);
        for (var i = 1; i <= 3; i++) {
          canvas.drawCircle(ctr, h * 0.09 * i, Paint()..color = Colors.white.withValues(alpha: 0.3 - i * 0.07)..style = PaintingStyle.stroke..strokeWidth = 3);
        }
        canvas.drawCircle(ctr, h * 0.08, white);
        _text(canvas, 'SOS', ctr, h * 0.075);
      case TileArtKind.leaderboard:
        final bw = w * 0.17;
        final base = h * 0.62;
        for (final (i, hh) in [(0, 0.22), (1, 0.34), (2, 0.16)]) {
          final x = w * 0.5 + (i - 1) * (bw + 8) - bw / 2;
          canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x, base - h * hh, bw, h * hh), topLeft: const Radius.circular(6), topRight: const Radius.circular(6)), white);
        }
        _star(canvas, Offset(w * 0.5, base - h * 0.34 - 14), 12, Paint()..color = c.amber500);
      case TileArtKind.rewards:
        final cup = Path()
          ..moveTo(w * 0.38, h * 0.16)
          ..lineTo(w * 0.62, h * 0.16)
          ..quadraticBezierTo(w * 0.62, h * 0.42, w * 0.5, h * 0.42)
          ..quadraticBezierTo(w * 0.38, h * 0.42, w * 0.38, h * 0.16)
          ..close();
        canvas.drawPath(cup, white);
        canvas.drawLine(Offset(w * 0.5, h * 0.42), Offset(w * 0.5, h * 0.52), line..strokeWidth = 5);
        canvas.drawLine(Offset(w * 0.42, h * 0.54), Offset(w * 0.58, h * 0.54), line);
        line.strokeWidth = 3;
        canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.34, h * 0.26), width: w * 0.12, height: h * 0.14), math.pi / 2, math.pi, false, line);
        canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.66, h * 0.26), width: w * 0.12, height: h * 0.14), -math.pi / 2, math.pi, false, line);
        for (final p in [Offset(w * 0.2, h * 0.2), Offset(w * 0.8, h * 0.18), Offset(w * 0.72, h * 0.5), Offset(w * 0.26, h * 0.48)]) {
          _star(canvas, p, 7, Paint()..color = c.amber500);
        }
      case TileArtKind.supervisorFeed:
        for (var i = 0; i < 3; i++) {
          final r = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.2, h * (0.14 + i * 0.14), w * 0.6, h * 0.1), const Radius.circular(8));
          canvas.drawRRect(r, i == 0 ? (Paint()..color = c.amber500.withValues(alpha: 0.5)) : white);
          canvas.drawCircle(Offset(w * 0.26, h * (0.19 + i * 0.14)), h * 0.025, Paint()..color = Colors.white.withValues(alpha: 0.7));
        }
      case TileArtKind.zones:
        for (var r = 0; r < 3; r++) {
          for (var q = 0; q < 4; q++) {
            final rect = Rect.fromLTWH(w * (0.16 + q * 0.17), h * (0.14 + r * 0.14), w * 0.15, h * 0.12);
            canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), (r + q) % 3 == 0 ? (Paint()..color = c.amber500.withValues(alpha: 0.55)) : white);
          }
        }
      case TileArtKind.crisis:
        // tunnel map with a route to an exit flag
        final grid = Paint()
          ..color = Colors.white.withValues(alpha: 0.14)
          ..strokeWidth = 2;
        for (var i = 1; i < 6; i++) {
          canvas.drawLine(Offset(w * i / 6, h * 0.08), Offset(w * i / 6, h * 0.62), grid);
          canvas.drawLine(Offset(w * 0.08, h * (0.08 + i * 0.09)), Offset(w * 0.92, h * (0.08 + i * 0.09)), grid);
        }
        final route = Path()
          ..moveTo(w * 0.18, h * 0.55)
          ..lineTo(w * 0.18, h * 0.35)
          ..lineTo(w * 0.5, h * 0.35)
          ..lineTo(w * 0.5, h * 0.2)
          ..lineTo(w * 0.8, h * 0.2);
        canvas.drawPath(route, Paint()..color = c.amber500..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
        canvas.drawCircle(Offset(w * 0.18, h * 0.55), 7, Paint()..color = c.positionBlue);
        _flag(canvas, Offset(w * 0.8, h * 0.2), h * 0.12, Paint()..color = c.successFill);
      case TileArtKind.reports:
        final bw = w * 0.1;
        for (var i = 0; i < 5; i++) {
          final hh = h * [0.14, 0.22, 0.17, 0.3, 0.38][i];
          canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(w * 0.2 + i * (bw + 8), h * 0.58 - hh, bw, hh), topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), white);
        }
        final trend = Path()
          ..moveTo(w * 0.2, h * 0.42)
          ..lineTo(w * 0.34, h * 0.34)
          ..lineTo(w * 0.5, h * 0.38)
          ..lineTo(w * 0.66, h * 0.24)
          ..lineTo(w * 0.82, h * 0.16);
        canvas.drawPath(trend, line..color = c.amber500);
      case TileArtKind.broadcast:
        final ctr = Offset(w * 0.4, h * 0.38);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: ctr, width: w * 0.16, height: h * 0.14), const Radius.circular(6)), white);
        final cone = Path()
          ..moveTo(w * 0.46, h * 0.31)
          ..lineTo(w * 0.62, h * 0.2)
          ..lineTo(w * 0.62, h * 0.56)
          ..lineTo(w * 0.46, h * 0.45)
          ..close();
        canvas.drawPath(cone, white);
        for (var i = 1; i <= 3; i++) {
          canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.62, h * 0.38), width: w * 0.12 * i, height: h * 0.14 * i), -0.7, 1.4, false, line..strokeWidth = 3);
        }
      case TileArtKind.contacts:
        final ctr = Offset(w * 0.5, h * 0.4);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: ctr, width: w * 0.2, height: h * 0.34), const Radius.circular(12)), white);
        canvas.drawCircle(Offset(w * 0.5, h * 0.52), 4, Paint()..color = Colors.white.withValues(alpha: 0.6));
        for (var i = 1; i <= 2; i++) {
          canvas.drawArc(Rect.fromCenter(center: ctr, width: w * 0.2 + i * 38, height: h * 0.34 + i * 38), -0.6, 1.2, false, line);
          canvas.drawArc(Rect.fromCenter(center: ctr, width: w * 0.2 + i * 38, height: h * 0.34 + i * 38), math.pi - 0.6, 1.2, false, line);
        }
      case TileArtKind.hero:
        // tunnel in perspective
        for (var i = 0; i < 5; i++) {
          final f = 1 - i * 0.18;
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.5, h * 0.4), width: w * 0.8 * f, height: h * 0.6 * f), Radius.circular(w * 0.2 * f)),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.08 + i * 0.03)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
        }
        _hardHat(canvas, Offset(w * 0.5, h * 0.4), w * 0.08, white);
    }
  }

  void _hardHat(Canvas canvas, Offset ctr, double r, Paint p) {
    canvas.drawArc(Rect.fromCircle(center: ctr, radius: r), math.pi, math.pi, true, p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: ctr.translate(0, r * 0.14), width: r * 2.5, height: r * 0.3), const Radius.circular(4)), p);
  }

  void _star(Canvas canvas, Offset ctr, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final ang = -math.pi / 2 + i * math.pi / 5;
      final pt = ctr + Offset(math.cos(ang) * rad, math.sin(ang) * rad);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), p);
  }

  void _flag(Canvas canvas, Offset base, double h, Paint p) {
    canvas.drawLine(base, base.translate(0, -h), Paint()..color = Colors.white..strokeWidth = 3);
    final f = Path()
      ..moveTo(base.dx, base.dy - h)
      ..lineTo(base.dx + h * 0.8, base.dy - h * 0.78)
      ..lineTo(base.dx, base.dy - h * 0.55)
      ..close();
    canvas.drawPath(f, p);
  }

  void _text(Canvas canvas, String t, Offset ctr, double size) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w900, letterSpacing: 1)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, ctr - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.kind != kind || old.c != c;
}
