import 'dart:math' as math;

import '../models/mine_layout.dart';
import 'local_frame.dart';

class MatchResult {
  const MatchResult({required this.x, required this.y, required this.tunnelId, required this.distanceM});
  final double x;
  final double y;
  final String tunnelId;
  final double distanceM;
}

class _Seg {
  const _Seg(this.id, this.ax, this.ay, this.bx, this.by);
  final String id;
  final double ax, ay, bx, by;
}

/// Snaps a position onto the nearest tunnel centre line of the cached layout (CLAUDE.md section 23.3), within [maxDistM].
class MapMatcher {
  MapMatcher(this._segs, {this.maxDistM = 15});
  final List<_Seg> _segs;
  final double maxDistM;

  factory MapMatcher.fromLayout(MineLayoutData layout, LocalFrame frame, {double maxDistM = 15}) {
    final segs = <_Seg>[];
    for (final t in layout.tunnels) {
      if (t.blocked) continue;
      for (var i = 0; i + 1 < t.coords.length; i++) {
        final a = frame.toXY(t.coords[i].lat, t.coords[i].lng);
        final b = frame.toXY(t.coords[i + 1].lat, t.coords[i + 1].lng);
        segs.add(_Seg(t.id, a.x, a.y, b.x, b.y));
      }
    }
    return MapMatcher(segs, maxDistM: maxDistM);
  }

  /// Builds a matcher from raw segments (tests).
  factory MapMatcher.segments(List<(String, double, double, double, double)> s, {double maxDistM = 15}) => MapMatcher([for (final x in s) _Seg(x.$1, x.$2, x.$3, x.$4, x.$5)], maxDistM: maxDistM);

  bool get isEmpty => _segs.isEmpty;

  MatchResult? snap(double x, double y) {
    MatchResult? best;
    for (final s in _segs) {
      final dx = s.bx - s.ax, dy = s.by - s.ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((x - s.ax) * dx + (y - s.ay) * dy) / len2).clamp(0.0, 1.0);
      final cx = s.ax + t * dx, cy = s.ay + t * dy;
      final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      if (d <= maxDistM && (best == null || d < best.distanceM)) best = MatchResult(x: cx, y: cy, tunnelId: s.id, distanceM: d);
    }
    return best;
  }
}
