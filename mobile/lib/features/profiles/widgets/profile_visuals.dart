import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_avatar.dart';
import '../../../app/ui/net_photo.dart';
import '../../../app/ui/pulse_dot.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../data/profile_models.dart';

/// Ring colour for today's check-in: compliant green, non-compliant red, awaiting review amber, none slate.
Color todayRing(MgColors c, TodayStatus? t) {
  if (t == null || !t.checkedIn) return c.slate400;
  return switch (t.verdict) {
    Verdict.compliant => c.success,
    Verdict.nonCompliant => c.danger,
    _ => c.amber500,
  };
}

String todayLabel(TodayStatus? t) {
  if (t == null) return '—';
  if (!t.checkedIn) return 'Not checked in';
  return t.verdict?.label ?? 'Awaiting review';
}

ChipTone todayTone(TodayStatus? t) {
  if (t == null || !t.checkedIn) return ChipTone.neutral;
  return switch (t.verdict) { Verdict.compliant => ChipTone.success, Verdict.nonCompliant => ChipTone.danger, _ => ChipTone.warning };
}

ChipTone bandTone(RiskBand b) => switch (b) { RiskBand.green => ChipTone.success, RiskBand.amber => ChipTone.warning, RiskBand.red => ChipTone.danger };
String bandLabel(RiskBand b) => switch (b) { RiskBand.green => 'Green', RiskBand.amber => 'Amber', RiskBand.red => 'Red' };

Color presenceColor(MgColors c, Presence? p) => switch (p) { Presence.live => c.success, Presence.stale => c.amber500, _ => c.slate400 };
String presenceLabel(Presence? p) => switch (p) { Presence.live => 'Live', Presence.stale => 'Stale', Presence.offline => 'Offline', null => 'Not tracked' };

/// Photo avatar with the status ring: the latest check-in photo when there is one, initials otherwise.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, this.photoUrl, this.ring, this.size = 52, this.presence, this.heroTag});
  final String name;
  final String? photoUrl;
  final Color? ring;
  final double size;
  final Presence? presence;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    Widget face = photoUrl == null || photoUrl!.isEmpty
        ? MgAvatar(name: name, size: size, ring: ring)
        : Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: ring == null ? null : Border.all(color: ring!, width: 3)),
            child: ClipOval(child: NetPhoto(url: photoUrl, fallbackIcon: Icons.person)),
          );
    if (heroTag != null) face = Hero(tag: heroTag!, child: face);
    if (presence == null) return Semantics(label: name, child: face);
    return Semantics(
      label: '$name, ${presenceLabel(presence)}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          face,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
              child: PulseDot(color: presenceColor(c, presence), size: 10, pulsing: presence == Presence.live),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 30 IST days, oldest first: one rounded cell per day coloured by that day's verdict (grey = no check-in).
class ComplianceStrip extends StatelessWidget {
  const ComplianceStrip({super.key, required this.days});
  final List<CalendarDay> days;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    Color col(CalendarDay d) => switch (d.verdict) {
          Verdict.compliant => c.success,
          Verdict.nonCompliant => c.danger,
          Verdict.needsManualReview => c.amber500,
          null => c.border,
        };
    final compliant = days.where((d) => d.verdict == Verdict.compliant).length;
    final non = days.where((d) => d.verdict == Verdict.nonCompliant).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        label: 'Last ${days.length} days: $compliant compliant, $non non-compliant',
        excludeSemantics: true,
        child: LayoutBuilder(builder: (context, box) {
          const gap = 3.0;
          final n = days.isEmpty ? 1 : days.length;
          final w = ((box.maxWidth - gap * (n - 1)) / n).clamp(4.0, 22.0);
          return Row(children: [
            for (var i = 0; i < days.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Tooltip(
                message: '${days[i].day}: ${days[i].verdict?.label ?? 'no check-in'}',
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: Motion.reduce(context) ? 1 : 0, end: 1),
                  duration: Motion.of(context, Motion.slower + Duration(milliseconds: 12 * i)),
                  curve: Motion.easeOut,
                  builder: (_, v, child) => Transform.scale(scaleY: v, alignment: Alignment.bottomCenter, child: child),
                  child: Container(width: w, height: 26, decoration: BoxDecoration(color: col(days[i]), borderRadius: BorderRadius.circular(4))),
                ),
              ),
            ],
          ]);
        }),
      ),
      const SizedBox(height: Space.sm),
      Wrap(spacing: Space.md, runSpacing: Space.xs, children: [
        _Legend(color: c.success, label: '$compliant compliant'),
        _Legend(color: c.danger, label: '$non non-compliant'),
        _Legend(color: c.amber500, label: 'review'),
        _Legend(color: c.border, label: 'no check-in'),
      ].map((w) => DefaultTextStyle.merge(style: t.labelSmall?.copyWith(color: c.muted), child: w)).toList()),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: Space.xs),
        Text(label),
      ]);
}

/// Score over the stored daily snapshots (no invented points: fewer than 2 snapshots shows a note instead).
class ScoreSparkline extends StatelessWidget {
  const ScoreSparkline({super.key, required this.history, this.height = 72});
  final List<(String, int)> history;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    if (history.length < 2) {
      return Text(history.isEmpty ? 'No score history yet' : 'Trend appears after the second daily score', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted));
    }
    final spots = [for (var i = 0; i < history.length; i++) FlSpot(i.toDouble(), history[i].$2.toDouble())];
    final lo = history.map((h) => h.$2).reduce((a, b) => a < b ? a : b).toDouble();
    final hi = history.map((h) => h.$2).reduce((a, b) => a > b ? a : b).toDouble();
    return Semantics(
      label: 'Score trend from ${history.first.$2} to ${history.last.$2}',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minY: (lo - 20).clamp(0, 1000),
            maxY: (hi + 20).clamp(0, 1000),
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                barWidth: 3,
                color: c.amber500,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.amber500.withValues(alpha: 0.35), c.amber500.withValues(alpha: 0)])),
              ),
            ],
          ),
          duration: Motion.of(context, Motion.slower),
        ),
      ),
    );
  }
}
