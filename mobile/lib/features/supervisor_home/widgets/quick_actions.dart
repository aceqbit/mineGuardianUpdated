import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_card.dart';

class QuickAction {
  const QuickAction({required this.icon, required this.label, required this.onTap, this.badge, this.tone});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Small count shown on the icon (e.g. check-ins waiting for review).
  final int? badge;
  final Color? tone;
}

/// One row of big icon buttons for what a supervisor does most.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key, required this.actions});
  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.only(right: Space.md),
            child: SizedBox(
              width: 112,
              child: MgCard(
                onTap: a.onTap,
                semanticLabel: a.label,
                padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.md),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Badge(
                    isLabelVisible: (a.badge ?? 0) > 0,
                    label: Text('${a.badge}'),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: (a.tone ?? c.amberText).withValues(alpha: 0.12)),
                      child: Icon(a.icon, color: a.tone ?? c.amberText),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(a.label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: t.labelMedium),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
