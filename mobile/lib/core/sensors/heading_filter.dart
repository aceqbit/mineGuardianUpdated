import 'dart:math' as math;

import 'local_frame.dart';

/// Device heading (degrees from magnetic north, of the phone's top edge).
/// Complementary filter: 0.98 × gyro-integrated heading + 0.02 × tilt-compensated magnetometer heading.
class HeadingFilter {
  HeadingFilter({this.gyroWeight = 0.98});
  final double gyroWeight;
  double? _h;
  DateTime? _lastGyro;

  double? get headingDeg => _h;

  /// Gyroscope z rate (rad/s, device frame). Counter-clockwise rotation lowers the azimuth.
  void addGyro(double gz, DateTime t) {
    final last = _lastGyro;
    _lastGyro = t;
    if (_h == null || last == null) return;
    final dt = t.difference(last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.5) return; // gap: wait for the next pair
    _h = wrapDeg(_h! - gz * dt * 180 / math.pi);
  }

  /// Magnetometer heading (already tilt-compensated). The first reading initialises the filter.
  void addMag(double magHeadingDeg) {
    final h = _h;
    _h = h == null ? wrapDeg(magHeadingDeg) : wrapDeg(h + (1 - gyroWeight) * angleDiffDeg(magHeadingDeg, h));
  }

  /// Azimuth of the device y axis from gravity [a] and the geomagnetic field [m] (Android getRotationMatrix maths):
  /// H = m × a, M = a × H, azimuth = atan2(Hy, My). Null when the phone is in free fall or the field is parallel to gravity.
  static double? tiltCompensated(double ax, double ay, double az, double mx, double my, double mz) {
    var hx = my * az - mz * ay;
    var hy = mz * ax - mx * az;
    var hz = mx * ay - my * ax;
    final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    final normA = math.sqrt(ax * ax + ay * ay + az * az);
    if (normH < 0.1 || normA < 0.1) return null;
    hx /= normH;
    hy /= normH;
    hz /= normH;
    final gx = ax / normA, gz = az / normA;
    final myv = gz * hx - gx * hz; // y component of a × H
    return wrapDeg(math.atan2(hy, myv) * 180 / math.pi);
  }
}
