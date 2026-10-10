import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../contracts/enums.dart';

/// 8 large single-select cards with icon, label, one-line hint, animated border and a check badge.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, required this.selected, required this.onSelected});
  final HazardCategory? selected;
  final ValueChanged<HazardCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return AdaptiveGrid(
      minTileWidth: 150,
      maxColumns: 4,
      fixedTileHeight: 152,
      children: [for (final c in HazardCategory.values) _Card(category: c, selected: selected == c, onTap: () => onSelected(c))],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.category, required this.selected, required this.onTap});
  final HazardCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${category.label}. ${category.hint}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        decoration: BoxDecoration(
          color: selected ? c.amber50 : c.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: selected ? c.amber500 : c.border, width: selected ? 2 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.card),
            onTap: onTap,
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(category.icon, size: 26, color: selected ? c.amberText : c.muted),
                  const SizedBox(height: Space.sm),
                  Text(category.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontSize: 14, color: selected ? c.ink900.withValues(alpha: 1) : c.text)),
                  const SizedBox(height: 2),
                  Text(category.hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(fontSize: 11, color: selected ? c.ink700 : c.muted)),
                ]),
              ),
              Positioned(
                top: Space.sm,
                right: Space.sm,
                child: AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: Motion.of(context, Motion.base),
                  curve: Curves.easeOutBack,
                  child: Container(width: 22, height: 22, decoration: BoxDecoration(color: c.amber500, shape: BoxShape.circle), child: Icon(Icons.check, size: 14, color: c.ink900)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
