import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/location/location_service.dart';
import '../../../core/models/mine_layout.dart';
import '../bloc/sos_state.dart';
import '../data/evac_graph.dart';

/// Draws the cached layout with no map tiles: zones, tunnels (width ~ widthM), junctions, exits, refuge,
/// cached hazards, routes, the user's live position, a north arrow. Projects [lng, lat] to local metres around the anchor.
class EvacMapPainter extends CustomPainter {
  EvacMapPainter({
    required this.layout,
    required this.colors,
    required this.ownZone,
    required this.fix,
    required this.hazards,
    required this.offlineRoute,
    required this.controlRoutes,
    required this.activeControl,
    this.pulse = 0,
  });

  final MineLayoutData layout;
  final MgColors colors;
  final String? ownZone;
  final LocationFix? fix;
  final List<CachedHazard> hazards;
  final EvacRoute? offlineRoute;
  final List<ControlRoute> controlRoutes;
  final ControlRoute? activeControl;
  final double pulse;

  static const double _pad = 28;

  ({double minX, double maxX, double minY, double maxY}) _bounds() {
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    void add(GeoPoint p) {
      final l = layout.toLocal(p);
      minX = math.min(minX, l.x);
      maxX = math.max(maxX, l.x);
      minY = math.min(minY, l.y);
      maxY = math.max(maxY, l.y);
    }

    for (final z in layout.zones) {
      z.ring.forEach(add);
    }
    for (final t in layout.tunnels) {
      t.coords.forEach(add);
    }
    return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final b = _bounds();
    final w = (b.maxX - b.minX).clamp(1, double.infinity);
    final h = (b.maxY - b.minY).clamp(1, double.infinity);
    final scale = math.min((size.width - 2 * _pad) / w, (size.height - 2 * _pad) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    Offset px(GeoPoint p) {
      final l = layout.toLocal(p);
      return Offset(ox + (l.x - b.minX) * scale, size.height - (oy + (l.y - b.minY) * scale));
    }

    final c = colors;
    // zones
    for (final z in layout.zones) {
      final path = Path()..addPolygon(z.ring.map(px).toList(), true);
      final own = z.code == ownZone;
      canvas.drawPath(path, Paint()..color = (own ? c.amber500 : c.slate400).withValues(alpha: own ? 0.10 : 0.06));
      canvas.drawPath(path, Paint()..color = own ? c.amberText : c.slate300..style = PaintingStyle.stroke..strokeWidth = own ? 2.5 : 1);
      final centre = path.getBounds().topCenter + const Offset(0, 14);
      _text(canvas, z.code, centre, c.muted, 12, bold: own);
    }
    // tunnels
    for (final t in layout.tunnels) {
      final p = Path()..moveTo(px(t.coords.first).dx, px(t.coords.first).dy);
      for (final pt in t.coords.skip(1)) {
        p.lineTo(px(pt).dx, px(pt).dy);
      }
      final width = math.max(2.0, t.widthM * scale * 0.9);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = t.blocked ? c.danger : (t.airway == 'intake' ? c.info : c.slate500);
      if (t.blocked) {
        _dashed(canvas, p, paint, 8, 5);
      } else {
        canvas.drawPath(p, paint..color = paint.color.withValues(alpha: 0.75));
      }
    }
    // junctions
    for (final j in layout.junctions) {
      canvas.drawCircle(px(j.point), 2.5, Paint()..color = c.ink700);
    }
    // offline route (amber)
    final off = offlineRoute;
    if (off != null) {
      final p = Path()..moveTo(px(off.points.first).dx, px(off.points.first).dy);
      for (final pt in off.points.skip(1)) {
        p.lineTo(px(pt).dx, px(pt).dy);
      }
      canvas.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..color = c.amber500);
    }
    // control-room routes: alternates thin dashed, active thick green
    for (final r in controlRoutes) {
      if (r == activeControl || r.points.length < 2) continue;
      final p = Path()..moveTo(px(r.points.first).dx, px(r.points.first).dy);
      for (final pt in r.points.skip(1)) {
        p.lineTo(px(pt).dx, px(pt).dy);
      }
      _dashed(canvas, p, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = c.success.withValues(alpha: 0.7), 7, 5);
    }
    final a = activeControl;
    if (a != null && a.points.length >= 2) {
      final p = Path()..moveTo(px(a.points.first).dx, px(a.points.first).dy);
      for (final pt in a.points.skip(1)) {
        p.lineTo(px(pt).dx, px(pt).dy);
      }
      canvas.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..color = c.success);
    }
    // exits (green circles with names) and refuge (blue square)
    for (final e in layout.exits) {
      final o = px(e.point);
      canvas.drawCircle(o, 9, Paint()..color = c.success);
      canvas.drawCircle(o, 9, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
      _text(canvas, e.name, o + const Offset(0, 16), c.text, 11, bold: true, center: true);
    }
    for (final r in layout.refuges) {
      final o = px(r.point);
      canvas.drawRect(Rect.fromCenter(center: o, width: 14, height: 14), Paint()..color = c.info);
      _text(canvas, 'RC', o, Colors.white, 8, bold: true, center: true);
    }
    // hazards (red triangles)
    for (final hz in hazards) {
      final o = px(hz.point);
      final tri = Path()..moveTo(o.dx, o.dy - 9)..lineTo(o.dx + 8, o.dy + 7)..lineTo(o.dx - 8, o.dy + 7)..close();
      canvas.drawPath(tri, Paint()..color = c.danger);
      _text(canvas, '!', o + const Offset(0, 2), Colors.white, 9, bold: true, center: true);
    }
    // user position + accuracy
    final f = fix;
    if (f != null) {
      final o = px(GeoPoint(f.lat, f.lng));
      final accR = (f.accuracyM * scale).clamp(6.0, 120.0);
      canvas.drawCircle(o, accR, Paint()..color = c.positionBlue.withValues(alpha: 0.15));
      canvas.drawCircle(o, 9 + 5 * pulse, Paint()..color = c.positionBlue.withValues(alpha: 0.25 * (1 - pulse)));
      canvas.drawCircle(o, 7, Paint()..color = c.positionBlue);
      canvas.drawCircle(o, 7, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }
    // north arrow
    final n = Offset(size.width - 26, 30);
    canvas.drawPath(Path()..moveTo(n.dx, n.dy - 14)..lineTo(n.dx + 7, n.dy + 8)..lineTo(n.dx, n.dy + 3)..lineTo(n.dx - 7, n.dy + 8)..close(), Paint()..color = c.ink700);
    _text(canvas, 'N', n + const Offset(0, 18), c.ink700, 11, bold: true, center: true);
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size, {bool bold = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant EvacMapPainter old) =>
      old.layout != layout || old.fix?.lat != fix?.lat || old.fix?.lng != fix?.lng || old.offlineRoute?.distanceM != offlineRoute?.distanceM || old.controlRoutes != controlRoutes || old.activeControl != activeControl || old.hazards.length != hazards.length || old.pulse != pulse || old.colors != colors;
}
