import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/score_ring.dart';
import '../data/models/feed_item.dart';
import '../../../contracts/enums.dart';

/// Readiness of the zone right now: a coverage ring (who has checked in) and where everyone stands.
class ZonePulse extends StatelessWidget {
  const ZonePulse({super.key, required this.workers});
  final List<WorkerToday> workers;

  int _count(bool Function(WorkerToday) f) => workers.where(f).length;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final total = workers.length;
    final checkedIn = _count((w) => w.status != 'NOT_CHECKED_IN');
    final rows = <(IconData, String, int, Color)>[
      (Icons.verified, 'Compliant', _count((w) => w.status == 'REVIEWED' && w.finalVerdict != Verdict.nonCompliant), c.success),
      (Icons.pending_actions, 'Needs review', _count((w) => w.status == 'PREDICTED' || w.status == 'FAILED_AI'), c.warning),
      (Icons.gpp_bad, 'Non-compliant', _count((w) => (w.finalVerdict ?? w.verdict) == Verdict.nonCompliant), c.danger),
      (Icons.person_off, 'Not checked in', _count((w) => w.status == 'NOT_CHECKED_IN'), c.muted),
    ];
    return MgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.monitor_heart, size: 18, color: c.amberText), const SizedBox(width: Space.sm), Text('Zone pulse', style: t.titleMedium)]),
        const SizedBox(height: Space.md),
        Row(children: [
          ScoreRing(value: total == 0 ? null : checkedIn, max: total == 0 ? 1 : total, size: 96, label: 'Checked in', center: Text(total == 0 ? '—' : '$checkedIn/$total', style: t.titleMedium)),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Row(children: [
                    Icon(r.$1, size: 16, color: r.$4),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(r.$2, style: t.bodySmall)),
                    Text('${r.$3}', style: t.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ),
            ]),
          ),
        ]),
      ]),
    );
  }
}
