import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/skeleton.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../core/time/ist.dart';
import '../data/models/checkin_summary.dart';

class RecentCheckins extends StatelessWidget {
  const RecentCheckins({super.key, required this.items, required this.loading, required this.flashIds});
  final List<CheckinSummary> items;
  final bool loading;
  final Set<String> flashIds;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 3);
    if (items.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: Space.x2), child: EmptyState(icon: Icons.photo_camera_outlined, title: 'No check-ins yet', message: 'Capture your shift photo to get started'));
    }
    return Column(children: [
      for (var i = 0; i < items.length; i++)
        StaggerIn(
          index: i,
          child: Padding(padding: const EdgeInsets.only(bottom: Space.md), child: _Tile(item: items[i], flash: flashIds.contains(items[i].id))),
        ),
    ]);
  }
}

(String, ChipTone) chipFor(CheckinSummary c) {
  switch (c.status) {
    case CheckinStatus.received:
    case CheckinStatus.analyzing:
      return ('AI checking', ChipTone.info);
    case CheckinStatus.predicted:
      return ('Awaiting supervisor', ChipTone.warning);
    case CheckinStatus.failedAi:
      return ('Manual review', ChipTone.warning);
    case CheckinStatus.rejectedQuality:
      return ('Retake needed', ChipTone.danger);
    case CheckinStatus.reviewed:
      return switch (c.finalVerdict) {
        Verdict.compliant => ('Compliant', ChipTone.success),
        Verdict.nonCompliant => ('Non-compliant', ChipTone.danger),
        _ => ('Reviewed', ChipTone.neutral),
      };
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.flash});
  final CheckinSummary item;
  final bool flash;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final (label, tone) = chipFor(item);
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: SizedBox(
        width: 56,
        height: 56,
        child: item.thumbUrl == null
            ? ColoredBox(color: c.slate100.withValues(alpha: 1), child: Icon(Icons.image, color: c.slate400))
            : CachedNetworkImage(imageUrl: item.thumbUrl!, cacheKey: 'checkin-${item.id}', fit: BoxFit.cover, placeholder: (_, _) => const Skeleton(radius: 0), errorWidget: (_, _, _) => Icon(Icons.broken_image, color: c.slate400)),
      ),
    );
    return AnimatedContainer(
      duration: Motion.of(context, Motion.slow),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.card), boxShadow: flash ? [BoxShadow(color: c.amber500.withValues(alpha: 0.5), blurRadius: 14)] : const []),
      child: MgCard(
        padding: const EdgeInsets.all(Space.md),
        child: Row(children: [
          Hero(tag: 'checkin-${item.id}', child: thumb),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatIst(item.capturedAt, pattern: 'd MMM · HH:mm'), style: t.titleMedium),
              const SizedBox(height: Space.xs),
              StatusChip(label: label, tone: tone),
              if (item.finalVerdict == Verdict.nonCompliant && item.missing.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text('Missing: ${item.missing.map((k) => k.label).join(', ')}', style: t.bodySmall?.copyWith(color: c.danger))),
            ]),
          ),
        ]),
      ),
    );
  }
}
