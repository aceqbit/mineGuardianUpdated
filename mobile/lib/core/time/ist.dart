import 'package:intl/intl.dart';

import '../../contracts/enums.dart';

/// All times are stored UTC and displayed in Asia/Kolkata (UTC+05:30, no DST).
const Duration istOffset = Duration(hours: 5, minutes: 30);

/// Wall-clock IST for a UTC instant. The returned DateTime is flagged UTC but holds IST wall time.
DateTime toIst(DateTime t) => t.toUtc().add(istOffset);

DateTime nowIst() => toIst(DateTime.now());

String formatIst(DateTime t, {String pattern = 'HH:mm'}) => DateFormat(pattern).format(toIst(t));

String formatIstTime(DateTime t) => '${formatIst(t, pattern: 'HH:mm:ss')} IST';

bool sameIstDay(DateTime a, DateTime b) {
  final x = toIst(a);
  final y = toIst(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

int _minutes(String hhmm) {
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// Whether [istWall] (already IST wall time) is within the shift window. Shift C wraps midnight.
bool isShiftOpen(Shift shift, DateTime istWall, {int toleranceMin = 0}) {
  final now = istWall.hour * 60 + istWall.minute;
  var start = _minutes(shift.start) - toleranceMin;
  var end = _minutes(shift.end) + toleranceMin;
  if (shift.end == '06:00' && shift.start == '22:00') {
    start = (start + 1440) % 1440;
    end = (end + 1440) % 1440;
    return now >= start || now < end;
  }
  return now >= start && now < end;
}

String relativeTime(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return DateFormat('d MMM, HH:mm').format(toIst(t));
}

/// Where [istWall] sits inside [shift]: whether it is open, how much of it has elapsed (0..1) and minutes left.
/// Shift C wraps midnight. Outside the window `open` is false and `fraction` is 0.
({bool open, double fraction, int minutesLeft}) shiftProgress(Shift shift, DateTime istWall) {
  if (!isShiftOpen(shift, istWall)) return (open: false, fraction: 0, minutesLeft: 0);
  final now = istWall.hour * 60 + istWall.minute;
  final start = _minutes(shift.start);
  var end = _minutes(shift.end);
  var elapsed = now - start;
  if (end <= start) end += 1440; // wraps midnight
  if (elapsed < 0) elapsed += 1440;
  final total = end - start;
  final f = (elapsed / total).clamp(0.0, 1.0);
  return (open: true, fraction: f, minutesLeft: (total - elapsed).clamp(0, total));
}

/// "Good morning" / "Good afternoon" / "Good evening" / "Night shift" by IST hour.
String greetingFor(DateTime istWall) {
  final h = istWall.hour;
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  if (h >= 17 && h < 21) return 'Good evening';
  return 'Stay safe tonight';
}
