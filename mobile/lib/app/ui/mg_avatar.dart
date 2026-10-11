import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Initials on a colour picked from the name (same name, same colour), with an optional status ring.
class MgAvatar extends StatelessWidget {
  const MgAvatar({super.key, required this.name, this.size = 44, this.ring});
  final String name;
  final double size;

  /// Status colour drawn as a ring around the avatar (null = no ring).
  final Color? ring;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final fills = [c.infoFill, c.successFill, c.warningFill, c.ink600, c.ink700];
    final fill = fills[name.codeUnits.fold<int>(0, (a, b) => a + b) % fills.length];
    final ringWidth = ring == null ? 0.0 : 3.0;
    return Semantics(
      label: name,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(ringWidth + (ring == null ? 0 : 2)),
        decoration: BoxDecoration(shape: BoxShape.circle, border: ring == null ? null : Border.all(color: ring!, width: ringWidth)),
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
          child: Center(child: Text(initialsOf(name), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800))),
        ),
      ),
    );
  }
}
