import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/read_aloud_button.dart';
import '../data/first_aid.dart';

Future<void> showFirstAidSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FirstAidSheet(),
    );

/// Seven short first-aid guides, all constants: works with no connection.
class FirstAidSheet extends StatelessWidget {
  const FirstAidSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          shrinkWrap: true,
          children: [
            Text('First aid', style: t.headlineSmall),
            const SizedBox(height: Space.md),
            for (final g in firstAidGuides)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Container(
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: c.border)),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: Icon(g.icon, color: c.danger),
                      title: Text(g.title, style: t.titleMedium),
                      childrenPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(alignment: Alignment.centerLeft, child: ReadAloudButton(owner: 'first-aid:${g.title}', label: 'Read aloud', segments: [g.title, ...g.steps])),
                        for (var i = 0; i < g.steps.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.sm),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: c.amber500, shape: BoxShape.circle), child: Text('${i + 1}', style: t.labelMedium?.copyWith(color: c.ink900))),
                              const SizedBox(width: Space.md),
                              Expanded(child: Text(g.steps[i], style: t.bodyMedium)),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: Space.sm),
            Text(firstAidFooter, style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}
