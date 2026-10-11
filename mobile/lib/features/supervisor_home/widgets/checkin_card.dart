import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/net_photo.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../core/time/ist.dart';
import '../data/models/feed_item.dart';

ChipTone verdictTone(Verdict? v) => switch (v) { Verdict.compliant => ChipTone.success, Verdict.nonCompliant => ChipTone.danger, Verdict.needsManualReview => ChipTone.warning, null => ChipTone.neutral };

IconData flagIcon(IntegrityFlag f) => switch (f) {
      IntegrityFlag.stalePhoto => Icons.history,
      IntegrityFlag.clockSkew => Icons.schedule,
      IntegrityFlag.noExif => Icons.info_outline,
      IntegrityFlag.duplicateHash => Icons.content_copy,
      IntegrityFlag.outsideZone => Icons.wrong_location,
      IntegrityFlag.lowGpsAccuracy => Icons.gps_not_fixed,
      IntegrityFlag.outOfShift => Icons.timer_off,
      IntegrityFlag.offlineDelayed => Icons.cloud_off,
      IntegrityFlag.gallerySource => Icons.photo_library,
    };

class CheckinCard extends StatelessWidget {
  const CheckinCard({super.key, required this.item, required this.onOpen});
  final CheckinFeed item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final r = item.review;
    final decided = r?.decided == true;

    Widget aiState;
    if (decided) {
      final label = switch (r!.action) { DecisionAction.confirm => 'Confirmed', DecisionAction.overrideAction => 'Overridden', DecisionAction.escalate => 'Escalated', null => 'Reviewed' };
      aiState = Row(children: [StatusChip(label: 'Reviewed · $label', tone: verdictTone(r.finalVerdict), icon: Icons.check)]);
    } else if (r == null || r.verdict == null) {
      aiState = item.status == CheckinStatus.failedAi
          ? const StatusChip(label: 'AI unavailable — decide manually', tone: ChipTone.warning)
          : Shimmer.fromColors(baseColor: c.muted, highlightColor: c.text, enabled: !Motion.reduce(context), child: Text('AI analysing…', style: t.bodyMedium));
    } else {
      aiState = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
          StatusChip(label: r.verdict!.label, tone: verdictTone(r.verdict)),
          if (r.critLevel != null) StatusChip(label: '${r.critLevel!.wire} ${r.critScore ?? ''}'.trim(), tone: r.critLevel == Criticality.critical || r.critLevel == Criticality.high ? ChipTone.danger : ChipTone.neutral),
          if (r.confidence != null) StatusChip(label: '${(r.confidence! * 100).round()}%', tone: ChipTone.neutral),
          if (r.emergencyDetected) const StatusChip(label: 'Emergency detected', tone: ChipTone.crisis) else if (r.emergencyPossible) const StatusChip(label: 'Possible emergency — review now', tone: ChipTone.warning, icon: Icons.priority_high),
        ]),
        if (r.summary != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(r.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
      ]);
    }

    return MgCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(Space.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Hero(
          tag: 'checkin-${item.id}',
          child: GestureDetector(
            onTap: item.thumbUrl == null ? null : () => showPhotoViewer(context, url: item.thumbUrl, title: '${item.workerName} · ${formatIstTime(item.time)}'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox(width: 88, height: 88, child: NetPhoto(url: item.thumbUrl, fallbackIcon: Icons.photo_camera_outlined)),
            ),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(item.workerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium)),
              Tooltip(message: formatIstTime(item.time), child: Text(relativeTime(item.time), style: t.bodySmall)),
            ]),
            if (item.flags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Wrap(spacing: Space.xs, children: [for (final f in item.flags) Tooltip(message: f.explanation, child: Icon(flagIcon(f), size: 16, color: c.warning))]),
              ),
            const SizedBox(height: Space.xs),
            aiState,
          ]),
        ),
      ]),
    );
  }
}
