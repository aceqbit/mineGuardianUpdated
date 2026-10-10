import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/stat_card.dart';
import '../data/models/checkin_summary.dart';

/// Four stat cards. Missing Phase 2 data renders "—" with a tooltip; numbers are never invented.
class StatsStrip extends StatelessWidget {
  const StatsStrip({super.key, required this.stats, required this.flash});
  final WorkerStats? stats;
  final bool flash;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final s = stats;
    final grid = AdaptiveGrid(
      fixedTileHeight: 128,
      maxColumns: 4,
      minTileWidth: 140,
      children: [
        StatCard(label: 'Safety score', value: s?.score, icon: Icons.shield, tone: flash ? c.amberText : null, hint: s == null ? null : 'of 1000'),
        StatCard(label: 'Streak', value: s?.streak, icon: Icons.local_fire_department, suffix: s == null ? '' : ' d', tone: flash ? c.amberText : null),
        StatCard(label: 'XP', value: s?.xp, icon: Icons.bolt, tone: flash ? c.amberText : null),
        StatCard(label: 'Rank', value: s?.rank, prefix: s == null ? null : '#', icon: Icons.emoji_events, tone: flash ? c.amberText : null),
      ],
    );
    if (s != null) return grid;
    return Tooltip(message: 'Scores appear once scoring is live', child: grid);
  }
}
