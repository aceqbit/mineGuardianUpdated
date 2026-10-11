import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_avatar.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/net_photo.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../core/time/ist.dart';
import '../data/models/feed_item.dart';
import 'checkin_card.dart' show verdictTone;
import 'worker_card.dart';

/// Everything about one worker today: latest photo (tap to zoom), status, risk, today's check-ins, call.
Future<void> showWorkerDetail(BuildContext context, {required WorkerToday worker, required List<CheckinFeed> checkins, required ValueChanged<String> onOpenCheckin}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final c = MgColors.of(ctx);
      final t = Theme.of(ctx).textTheme;
      final (label, tone) = workerChip(worker);
      final mine = checkins.where((x) => x.workerId == worker.id).toList()..sort((a, b) => b.time.compareTo(a.time));
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
          child: ListView(padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg), children: [
            Row(children: [
              MgAvatar(name: worker.fullName, size: 64, ring: workerRing(c, worker)),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(worker.fullName, style: t.headlineSmall),
                  Text(worker.employeeId, style: t.bodyMedium),
                  const SizedBox(height: Space.xs),
                  Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
                    StatusChip(label: label, tone: tone),
                    if (worker.riskBand != null) StatusChip(label: 'Risk ${worker.riskBand!.wire.toLowerCase()}', tone: switch (worker.riskBand!) { RiskBand.green => ChipTone.success, RiskBand.amber => ChipTone.warning, RiskBand.red => ChipTone.danger }, icon: Icons.shield),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: Space.lg),
            if (worker.thumbUrl != null)
              GestureDetector(
                onTap: () => showPhotoViewer(ctx, url: worker.thumbUrl, title: '${worker.fullName} · latest check-in'),
                child: ClipRRect(borderRadius: BorderRadius.circular(Radii.card), child: AspectRatio(aspectRatio: 16 / 9, child: NetPhoto(url: worker.thumbUrl, fallbackIcon: Icons.photo_camera_outlined))),
              )
            else
              Container(
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(color: c.surfaceTint, borderRadius: BorderRadius.circular(Radii.card)),
                child: Row(children: [Icon(Icons.photo_camera_outlined, color: c.muted), const SizedBox(width: Space.md), Expanded(child: Text('No check-in photo today yet', style: t.bodyMedium))]),
              ),
            const SizedBox(height: Space.lg),
            Text("Today's check-ins · ${worker.count}", style: t.titleMedium),
            const SizedBox(height: Space.sm),
            if (mine.isEmpty) Text('Nothing received yet.', style: t.bodySmall),
            for (final ci in mine)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(borderRadius: BorderRadius.circular(Radii.sm), child: SizedBox(width: 48, height: 48, child: NetPhoto(url: ci.thumbUrl))),
                title: Text(formatIstTime(ci.time)),
                subtitle: Text(relativeTime(ci.time)),
                trailing: ci.review?.verdict == null ? const Icon(Icons.hourglass_top) : StatusChip(label: (ci.review!.finalVerdict ?? ci.review!.verdict!).label, tone: verdictTone(ci.review!.finalVerdict ?? ci.review!.verdict)),
                onTap: () {
                  Navigator.pop(ctx);
                  onOpenCheckin(ci.id);
                },
              ),
            if (worker.phone != null) ...[
              const SizedBox(height: Space.md),
              MgButton(label: 'Call ${worker.fullName.split(' ').first}', icon: Icons.call, expand: true, kind: MgButtonKind.secondary, onPressed: () => launchUrl(Uri(scheme: 'tel', path: worker.phone))),
            ],
          ]),
        ),
      );
    },
  );
}
