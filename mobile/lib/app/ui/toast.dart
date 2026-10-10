import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum ToastKind { info, success, error, warning }

class Toast {
  Toast._();

  static void show(BuildContext context, String message, {ToastKind kind = ToastKind.info, Duration duration = const Duration(seconds: 3)}) {
    final c = MgColors.of(context);
    final (bg, icon) = switch (kind) {
      ToastKind.success => (c.successFill, Icons.check_circle),
      ToastKind.error => (c.dangerFill, Icons.error),
      ToastKind.warning => (c.warningFill, Icons.warning_amber),
      ToastKind.info => (c.ink700, Icons.info),
    };
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        duration: duration,
        margin: const EdgeInsets.all(Space.lg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: Space.md),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white))),
        ]),
      ));
  }
}
