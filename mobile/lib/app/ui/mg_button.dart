import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';
import '../theme/tokens.dart';

enum MgButtonKind { primary, secondary, danger, ghost }

class MgButton extends StatefulWidget {
  const MgButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = MgButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final MgButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final String? semanticLabel;

  @override
  State<MgButton> createState() => _MgButtonState();
}

class _MgButtonState extends State<MgButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final enabled = widget.onPressed != null && !widget.loading;
    final (bg, fg, border) = switch (widget.kind) {
      MgButtonKind.primary => (c.amber500, c.ink900, Colors.transparent),
      MgButtonKind.secondary => (c.surface, c.text, c.border),
      MgButtonKind.danger => (c.dangerFill, Colors.white, Colors.transparent),
      MgButtonKind.ghost => (Colors.transparent, c.text, Colors.transparent),
    };
    final child = AnimatedSwitcher(
      duration: Motion.of(context, Motion.base),
      child: widget.loading
          ? SizedBox(key: const ValueKey('l'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          : Row(
              key: const ValueKey('t'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[Icon(widget.icon, size: 20, color: fg), const SizedBox(width: Space.sm)],
                Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg))),
              ],
            ),
    );
    final button = AnimatedScale(
      scale: _down && enabled && !Motion.reduce(context) ? Motion.pressScale : 1,
      duration: Motion.fast,
      child: Opacity(
        opacity: enabled || widget.loading ? 1 : 0.5,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onPressed!();
                  }
                : null,
            onHighlightChanged: (v) => setState(() => _down = v),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.md),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.sm), border: Border.all(color: border)),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: widget.expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
