import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'mg_button.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.amber50, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: c.amberText),
            ),
            const SizedBox(height: Space.lg),
            Text(title, textAlign: TextAlign.center, style: t.titleMedium),
            if (message != null) ...[const SizedBox(height: Space.xs), Text(message!, textAlign: TextAlign.center, style: t.bodySmall)],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Space.lg),
              MgButton(label: actionLabel!, onPressed: onAction, kind: MgButtonKind.secondary),
            ],
          ],
        ),
      ),
    );
  }
}
