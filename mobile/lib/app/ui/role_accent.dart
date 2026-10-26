import 'package:flutter/material.dart';

import '../../contracts/enums.dart';
import '../theme/tokens.dart';

/// Role accents (CLAUDE.md section 23.7): miner amber, supervisor info teal, admin indigo.
/// [fill] carries white (or ink for amber) text; [text] is for text and icons on a surface.
class RoleAccent {
  const RoleAccent({required this.fill, required this.text, required this.onFill});
  final Color fill;
  final Color text;
  final Color onFill;

  static RoleAccent of(BuildContext context, Role role) {
    final c = MgColors.of(context);
    return switch (role) {
      Role.miner => RoleAccent(fill: c.amber500, text: c.amberText, onFill: c.ink900),
      Role.supervisor => RoleAccent(fill: c.infoFill, text: c.info, onFill: Colors.white),
      Role.admin => RoleAccent(fill: c.roleAdmin, text: c.roleAdminText, onFill: Colors.white),
    };
  }
}
