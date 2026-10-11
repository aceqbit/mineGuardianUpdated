import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_avatar.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/net_photo.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../core/time/ist.dart';
import '../data/models/feed_item.dart';

/// Today's status as a chip label and tone.
(String, ChipTone) workerChip(WorkerToday w) {
  switch (w.status) {
    case 'NOT_CHECKED_IN':
      return ('Not checked in', ChipTone.neutral);
    case 'RECEIVED':
    case 'ANALYZING':
      return ('AI checking', ChipTone.info);
    case 'PREDICTED':
      return ('Awaiting review', ChipTone.warning);
    case 'FAILED_AI':
      return ('Manual review', ChipTone.warning);
    case 'REVIEWED':
      return w.finalVerdict == Verdict.nonCompliant ? ('Non-compliant', ChipTone.danger) : ('Compliant', ChipTone.success);
    default:
      return (w.status, ChipTone.neutral);
  }
}

Color riskColor(MgColors c, RiskBand b) => switch (b) { RiskBand.green => c.success, RiskBand.amber => c.warning, RiskBand.red => c.danger };

/// Ring colour around a worker's avatar: today's outcome at a glance.
Color workerRing(MgColors c, WorkerToday w) {
  if (w.status == 'NOT_CHECKED_IN') return c.slate300;
  if (w.status == 'REVIEWED') return w.finalVerdict == Verdict.nonCompliant ? c.danger : c.success;
  if (w.status == 'PREDICTED' || w.status == 'FAILED_AI') return c.warning;
  return c.info;
}

/// One worker: avatar with status ring, name, ID, today's chip, risk band, and the latest check-in photo.
class WorkerCard extends StatelessWidget {
  const WorkerCard({super.key, required this.worker, required this.onTap});
  final WorkerToday worker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final w = worker;
    final (label, tone) = workerChip(w);
    final last = w.capturedAt;
    return MgCard(
      onTap: onTap,
      semanticLabel: '${w.fullName}, ${w.employeeId}, $label',
      padding: const EdgeInsets.all(Space.md),
      child: Row(children: [
        MgAvatar(name: w.fullName, size: 52, ring: workerRing(c, w)),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(w.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
            Text(w.employeeId, style: t.bodySmall),
            const SizedBox(height: Space.xs),
            Wrap(spacing: Space.sm, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusChip(label: label, tone: tone),
              if (w.riskBand != null) Tooltip(message: 'Risk ${w.riskBand!.wire.toLowerCase()}', child: Icon(Icons.shield, size: 18, color: riskColor(c, w.riskBand!))),
            ]),
            if (last != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text('Last photo ${relativeTime(last)} · ${w.count} today', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
          ]),
        ),
        const SizedBox(width: Space.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: SizedBox(width: 64, height: 64, child: NetPhoto(url: w.thumbUrl, fallbackIcon: Icons.photo_camera_outlined)),
        ),
      ]),
    );
  }
}
