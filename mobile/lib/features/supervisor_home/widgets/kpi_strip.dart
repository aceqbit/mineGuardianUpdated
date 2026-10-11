import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_card.dart';

class KpiData {
  const KpiData({required this.label, required this.value, required this.icon, this.tone});
  final String label;
  final String value;
  final IconData icon;
  final Color? tone;

}

/// "Checked in today x / y", Awaiting review, Open hazards, Active SOS (tinted above 0): a coloured icon badge, a big number, a label.
class KpiStrip extends StatelessWidget {
  const KpiStrip({super.key, required this.items});
  final List<KpiData> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    return AdaptiveGrid(
      fixedTileHeight: 104,
      minTileWidth: 150,
      maxColumns: 4,
      children: [
        for (final k in items)
          Semantics(
            label: '${k.label} ${k.value}',
            child: MgCard(
              tone: k.tone?.withValues(alpha: 0.08),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: (k.tone ?? c.amberText).withValues(alpha: 0.14)),
                  child: Icon(k.icon, color: k.tone ?? c.amberText),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(k.value, style: t.headlineMedium?.copyWith(color: k.tone))),
                    Text(k.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(color: c.muted)),
                  ]),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}
