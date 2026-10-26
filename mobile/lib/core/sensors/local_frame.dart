import 'dart:math' as math;

/// Local metre grid around an anchor (same maths as backend core/geo.js `metersToLatLng`):
/// dLat = y / 111320, dLng = x / (111320 · cos lat). Good to well under a metre across a mine.
class LocalFrame {
  LocalFrame(this.anchorLat, this.anchorLng) : _cos = math.cos(anchorLat * math.pi / 180);
  final double anchorLat;
  final double anchorLng;
  final double _cos;
  static const double _k = 111320.0;

  ({double x, double y}) toXY(double lat, double lng) => (x: (lng - anchorLng) * _k * _cos, y: (lat - anchorLat) * _k);

  ({double lat, double lng}) toLatLng(double x, double y) => (lat: anchorLat + y / _k, lng: anchorLng + x / (_k * _cos));
}

/// Smallest signed difference a − b in degrees, in (−180, 180].
double angleDiffDeg(double a, double b) {
  var d = (a - b) % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

double wrapDeg(double a) {
  final w = a % 360;
  return w < 0 ? w + 360 : w;
}
