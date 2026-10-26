import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/animated_counter.dart';
import '../../../app/ui/glass_card.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../data/profile_models.dart';
import 'profile_visuals.dart';

/// Fixed height of a profile card in the grid (the content is laid out to fit it at every width).
const double profileCardHeight = 184;

/// One person in the profile manager (CLAUDE.md section 23.2). Crew cards show only the public card.
class ProfileCardTile extends StatelessWidget {
  const ProfileCardTile({super.key, required this.card, required this.onTap, this.isMe = false, this.accent});
  final ProfileCard card;
  final VoidCallback onTap;
  final bool isMe;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final sub = [card.employeeId, if (card.designation != null && card.designation!.isNotEmpty) card.designation!].join(' · ');
    final staffView = card.level == ProfileLevel.full;
    return GlassCard(
      onTap: onTap,
      accent: accent,
      semanticLabel: '${card.fullName}${isMe ? ' (you)' : ''}, ${card.role.label}, ${todayLabel(card.today)}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProfileAvatar(name: card.fullName, photoUrl: card.photo?.url, ring: card.role == Role.miner ? todayRing(c, card.today) : null, presence: card.presence),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(card.fullName, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (isMe) ...[const SizedBox(width: Space.xs), Text('· you', style: t.labelMedium?.copyWith(color: c.amberText))],
              ]),
              Text(sub, style: t.bodySmall?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (staffView && card.riskBand != null) StatusChip(label: bandLabel(card.riskBand!), tone: bandTone(card.riskBand!)),
        ]),
        const SizedBox(height: Space.md),
        SizedBox(
          height: 28,
          child: ListView(scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), children: [
            StatusChip(label: card.role.label, tone: card.role == Role.miner ? ChipTone.neutral : ChipTone.info, icon: card.role == Role.admin ? Icons.admin_panel_settings : (card.role == Role.supervisor ? Icons.supervisor_account : Icons.engineering)),
            if (card.zone != null) ...[const SizedBox(width: Space.xs), StatusChip(label: card.zone!.code, icon: Icons.place)],
            if (card.shift != null) ...[const SizedBox(width: Space.xs), StatusChip(label: 'Shift ${card.shift!.wire}', icon: Icons.schedule)],
            if (!card.active) ...[const SizedBox(width: Space.xs), const StatusChip(label: 'Inactive', tone: ChipTone.danger)],
            if (card.role == Role.miner && card.today != null) ...[const SizedBox(width: Space.xs), StatusChip(label: todayLabel(card.today), tone: todayTone(card.today))],
          ]),
        ),
        const Spacer(),
        Row(children: [
          if (card.score != null) Expanded(child: _Stat(label: 'Score', value: card.score)),
          if (card.rank != null) Expanded(child: _Stat(label: 'Rank', value: card.rank, prefix: '#')),
          Expanded(child: _Stat(label: 'Streak', value: card.streak, suffix: 'd')),
          Expanded(child: _Stat(label: 'XP', value: card.xp)),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.prefix = '', this.suffix = ''});
  final String label;
  final int? value;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: t.labelSmall?.copyWith(color: c.muted)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (prefix.isNotEmpty && value != null) Text(prefix, style: t.titleMedium),
        Flexible(child: AnimatedCounter(value: value, suffix: suffix, style: t.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
      ]),
    ]);
  }
}
