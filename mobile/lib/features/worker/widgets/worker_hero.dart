import 'package:flutter/material.dart';

import '../../../app/app_images.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_hero_header.dart';
import '../../../app/ui/pulse_dot.dart';
import '../../../app/ui/score_ring.dart';
import '../../../contracts/enums.dart';
import '../../../core/models/session_user.dart';
import '../../../core/time/ist.dart';
import '../data/models/checkin_summary.dart';

/// Top of the worker home: greeting, zone, live connection dot, safety-score ring and a shift progress bar with time left.
class WorkerHero extends StatelessWidget {
  const WorkerHero({super.key, required this.user, required this.connected, required this.stats, this.now});
  final SessionUser user;
  final Stream<bool> connected;
  final WorkerStats? stats;

  /// Injected clock for tests (IST wall time).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final wall = now ?? nowIst();
    final shift = user.shift;
    return MgHeroHeader(
      eyebrow: greetingFor(wall).toUpperCase(),
      title: 'Hi ${user.firstName}',
      subtitle: [if (user.zoneCode != null) '${user.zoneCode} · ${user.zoneName ?? ''}'].join(),
      imageUrl: AppImages.loginHero,
      trailing: Column(mainAxisSize: MainAxisSize.min, children: [
        StreamBuilder<bool>(
          stream: connected,
          initialData: false,
          builder: (context, snap) => Tooltip(
            message: snap.data == true ? 'Live' : 'Offline',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              PulseDot(color: snap.data == true ? c.success : c.slate400, pulsing: snap.data == true),
              const SizedBox(width: Space.xs),
              Text(snap.data == true ? 'Live' : 'Offline', style: t.labelSmall?.copyWith(color: Colors.white70)),
            ]),
          ),
        ),
        const SizedBox(height: Space.sm),
        ScoreRing(value: stats?.score, size: 88, label: 'score', onDark: true),
      ]),
      child: shift == null ? null : _ShiftBar(shift: shift, wall: wall),
    );
  }
}

class _ShiftBar extends StatelessWidget {
  const _ShiftBar({required this.shift, required this.wall});
  final Shift shift;
  final DateTime wall;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final p = shiftProgress(shift, wall);
    final left = p.minutesLeft;
    final label = p.open ? '${left ~/ 60}h ${left % 60}m left' : 'Shift closed';
    return Semantics(
      label: 'Shift ${shift.wire}, ${shift.window}, ${p.open ? '${left ~/ 60} hours ${left % 60} minutes left' : 'closed'}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(p.open ? Icons.schedule : Icons.bedtime_outlined, size: 16, color: p.open ? c.amber500 : c.slate400),
          const SizedBox(width: Space.xs),
          Expanded(child: Text('Shift ${shift.wire} · ${shift.window}', style: t.labelLarge?.copyWith(color: Colors.white))),
          Text(label, style: t.labelMedium?.copyWith(color: p.open ? c.amber500 : c.slate300)),
        ]),
        const SizedBox(height: Space.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p.fraction),
            duration: Motion.of(context, Motion.slower),
            curve: Motion.easeOut,
            builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: Colors.white.withValues(alpha: 0.18), color: c.amber500),
          ),
        ),
      ]),
    );
  }
}
