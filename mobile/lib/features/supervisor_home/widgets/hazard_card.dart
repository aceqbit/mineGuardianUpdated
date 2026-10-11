import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/net_photo.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../core/time/ist.dart';
import '../data/models/feed_item.dart';

ChipTone severityTone(HazardSeverity? s) => switch (s) { HazardSeverity.critical => ChipTone.crisis, HazardSeverity.medium => ChipTone.warning, HazardSeverity.low => ChipTone.neutral, null => ChipTone.neutral };

ChipTone statusTone(HazardStatus s) => switch (s) { HazardStatus.open => ChipTone.danger, HazardStatus.acknowledged => ChipTone.warning, HazardStatus.closed => ChipTone.success, HazardStatus.rejected => ChipTone.neutral };

class HazardCard extends StatelessWidget {
  const HazardCard({super.key, required this.item, required this.onOpen, required this.onAcknowledge, required this.onClose, required this.onReject});
  final HazardFeed item;
  final VoidCallback onOpen;
  final VoidCallback onAcknowledge;
  final VoidCallback onClose;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final active = item.status == HazardStatus.open || item.status == HazardStatus.acknowledged;
    return MgCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(Space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Hero(
            tag: 'hazard-${item.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox(width: 64, height: 64, child: NetPhoto(url: item.thumbUrl, fallbackIcon: item.category.icon)),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(item.category.icon, size: 18, color: c.danger),
                const SizedBox(width: Space.xs),
                Expanded(child: Text(item.category.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium)),
              ]),
              Text('${item.reporterName} · ${relativeTime(item.time)}', style: t.bodySmall),
              const SizedBox(height: Space.xs),
              Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
                if (item.severity != null) StatusChip(label: item.severity!.wire, tone: severityTone(item.severity)),
                StatusChip(label: item.status.wire, tone: statusTone(item.status)),
              ]),
              if (item.aiSummary != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(item.aiSummary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
            ]),
          ),
        ]),
        if (active) ...[
          const SizedBox(height: Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            if (item.status == HazardStatus.open) MgButton(label: 'Acknowledge', kind: MgButtonKind.secondary, onPressed: onAcknowledge),
            MgButton(label: 'Close', onPressed: onClose),
            MgButton(label: 'Reject', kind: MgButtonKind.ghost, onPressed: onReject),
          ]),
        ],
      ]),
    );
  }
}
