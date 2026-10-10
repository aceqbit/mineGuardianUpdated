import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../app/app_images.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/skeleton.dart';
import '../data/admin_repository.dart';

class ZoneCard extends StatelessWidget {
  const ZoneCard({super.key, required this.zone, required this.onManage, this.exits = const [], this.onExitChosen});
  final ZoneOverview zone;
  final VoidCallback onManage;
  final List<ExitRef> exits;
  final ValueChanged<String?>? onExitChosen;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final frac = zone.minersCount == 0 ? 0.0 : (zone.checkedInToday / zone.minersCount).clamp(0.0, 1.0);
    return MgCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.card)),
          child: SizedBox(
            height: 96,
            child: Stack(fit: StackFit.expand, children: [
              CachedNetworkImage(imageUrl: AppImages.adminZones, fit: BoxFit.cover, placeholder: (_, _) => const Skeleton(radius: 0), errorWidget: (_, _, _) => ColoredBox(color: c.ink700)),
              ColoredBox(color: c.ink900.withValues(alpha: 0.6)),
              Center(child: Text(zone.code, style: t.displayLarge?.copyWith(color: Colors.white))),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(zone.name, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.sm),
            if (zone.supervisors.isEmpty) Text('No supervisor assigned', style: t.bodySmall?.copyWith(color: c.warning)),
            for (final s in zone.supervisors) Text('${s.fullName} · ${s.phoneMasked}', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.md),
            Text('${zone.minersCount} miners', style: t.bodyMedium),
            const SizedBox(height: Space.xs),
            Text('Checked in today ${zone.checkedInToday}/${zone.minersCount}', style: t.labelMedium),
            const SizedBox(height: Space.xs),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: frac, minHeight: 6, backgroundColor: c.border, color: c.success)),
            if (exits.isNotEmpty && onExitChosen != null) ...[
              const SizedBox(height: Space.md),
              Text('Emergency exit', style: t.labelMedium),
              const SizedBox(height: Space.xs),
              DropdownButton<String?>(
                isExpanded: true,
                value: exits.any((e) => e.id == zone.evacExitId) ? zone.evacExitId : null,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nearest safe exit (automatic)', overflow: TextOverflow.ellipsis)),
                  for (final e in exits) DropdownMenuItem<String?>(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: onExitChosen,
              ),
            ],
            const SizedBox(height: Space.md),
            MgButton(label: 'Manage supervisors', kind: MgButtonKind.secondary, icon: Icons.manage_accounts, expand: true, onPressed: onManage),
          ]),
        ),
      ]),
    );
  }
}
