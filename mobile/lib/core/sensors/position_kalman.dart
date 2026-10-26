import 'dart:math' as math;

/// 2-D position Kalman filter in local metres (CLAUDE.md section 23.3).
/// Motion model = pedestrian dead-reckoning steps; measurements = GPS fixes weighted by their accuracy (r = accuracy²).
/// Both axes share one variance because GPS accuracy is reported as a radius.
class PositionKalman {
  double x = 0;
  double y = 0;
  double p = 0;
  bool initialized = false;

  /// Variance added per walked metre (step length uncertainty and heading drift).
  static const double qPerMetre = 0.09;

  /// Variance added per second while standing (slow drift of an unobserved position).
  static const double qPerSecond = 0.02;

  void reset(double x0, double y0, double variance) {
    x = x0;
    y = y0;
    p = variance;
    initialized = true;
  }

  /// Dead-reckoning step of length [lengthM] towards [headingDeg] (0 = north = +y, 90 = east = +x).
  void step(double lengthM, double headingDeg) {
    if (!initialized) return;
    final r = headingDeg * math.pi / 180;
    x += lengthM * math.sin(r);
    y += lengthM * math.cos(r);
    p += qPerMetre * lengthM;
  }

  void elapse(double seconds) {
    if (initialized && seconds > 0) p += qPerSecond * seconds;
  }

  /// GPS measurement with radius [accuracyM].
  void update(double zx, double zy, double accuracyM) {
    final r = math.max(1.0, accuracyM * accuracyM);
    if (!initialized) {
      reset(zx, zy, r);
      return;
    }
    final k = p / (p + r);
    x += k * (zx - x);
    y += k * (zy - y);
    p = (1 - k) * p;
  }

  /// 1-sigma radius in metres.
  double get sigmaM => math.sqrt(p);
}
