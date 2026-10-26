import 'dart:math' as math;

/// Pedestrian step detector on the accelerometer magnitude (CLAUDE.md section 23.3).
/// Low-pass the magnitude, count a local peak above [thresholdMs2] (1.2 g) with at least [minGap] between steps.
/// Step length is 0.7 m, or the Weinberg estimate `k · (aMax − aMin)^¼` once [weinbergK] is calibrated.
class StepDetector {
  StepDetector({this.thresholdMs2 = 1.2 * 9.80665, this.minGap = const Duration(milliseconds: 300), this.alpha = 0.3, this.defaultStepM = 0.7, this.weinbergK});

  final double thresholdMs2;
  final Duration minGap;
  final double alpha;
  final double defaultStepM;
  double? weinbergK;

  double? _lp;
  double _prev = 0;
  double _prev2 = 0;
  DateTime? _prevT;
  DateTime? _lastStep;
  double _min = double.infinity;
  double _max = 0;
  int steps = 0;

  /// Feeds one accelerometer sample (m/s², gravity included). Returns the step length in metres when a step completes.
  double? add(double ax, double ay, double az, DateTime t) {
    final m = math.sqrt(ax * ax + ay * ay + az * az);
    _lp = _lp == null ? m : _lp! + alpha * (m - _lp!);
    final cur = _lp!;
    _min = math.min(_min, cur);
    _max = math.max(_max, cur);
    double? out;
    final peakT = _prevT;
    if (peakT != null && _prev > _prev2 && _prev >= cur && _prev > thresholdMs2) {
      if (_lastStep == null || peakT.difference(_lastStep!) >= minGap) {
        _lastStep = peakT;
        steps += 1;
        out = _stepLength();
        _min = cur;
        _max = cur;
      }
    }
    _prev2 = _prev;
    _prev = cur;
    _prevT = t;
    return out;
  }

  double _stepLength() {
    final k = weinbergK;
    if (k == null || !_min.isFinite || _max <= _min) return defaultStepM;
    return (k * math.pow(_max - _min, 0.25)).clamp(0.3, 1.2).toDouble();
  }
}
