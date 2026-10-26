import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';

double _lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final entry in {'light': MgColors.light, 'dark': MgColors.dark}.entries) {
    final c = entry.value;
    final pairs = <String, (Color, Color)>{
      'text on bg': (c.text, c.bg),
      'text on surface': (c.text, c.surface),
      'muted on bg': (c.muted, c.bg),
      'muted on surface': (c.muted, c.surface),
      'ink900 on amber500 (button text)': (c.ink900, c.amber500),
      'amberText on surface': (c.amberText, c.surface),
      'amberText on bg': (c.amberText, c.bg),
      'white on successFill': (Colors.white, c.successFill),
      'white on dangerFill': (Colors.white, c.dangerFill),
      'white on warningFill': (Colors.white, c.warningFill),
      'white on infoFill': (Colors.white, c.infoFill),
      'amberText on surfaceTint': (c.amberText, c.surfaceTint),
      'text on surfaceTint': (c.text, c.surfaceTint),
      'muted on surfaceTint': (c.muted, c.surfaceTint),
      'success on surface': (c.success, c.surface),
      'danger on surface': (c.danger, c.surface),
      'warning on surface': (c.warning, c.surface),
      'info on surface': (c.info, c.surface),
      'medalGold on surface': (c.medalGold, c.surface),
      'medalSilver on surface': (c.medalSilver, c.surface),
      'medalBronze on surface': (c.medalBronze, c.surface),
      'white on crisis': (Colors.white, c.crisis),
      'success on successBg': (c.success, c.successBg),
      'danger on dangerBg': (c.danger, c.dangerBg),
      'warning on warningBg': (c.warning, c.warningBg),
      'info on infoBg': (c.info, c.infoBg),
      'white on ink900': (Colors.white, c.ink900),
      'amber500 on ink900': (c.amber500, c.ink900),
      'slate300 on ink900': (c.slate300, c.ink900),
      'white on roleAdmin': (Colors.white, c.roleAdmin),
      'slate100 on ink900 (feature dock, light)': (c.slate100, c.ink900),
      'slate100 on ink800 (feature dock, dark)': (c.slate100, c.ink800),
      'slate300 on ink800 (dock role label)': (c.slate300, c.ink800),
      'roleAdminText on surface': (c.roleAdminText, c.surface),
      'roleAdminText on bg': (c.roleAdminText, c.bg),
    };
    for (final p in pairs.entries) {
      test('${entry.key}: ${p.key} meets WCAG AA (4.5:1)', () {
        final r = ratio(p.value.$1, p.value.$2);
        expect(r, greaterThanOrEqualTo(4.5), reason: '${p.key} is only ${r.toStringAsFixed(2)}:1');
      });
    }
  }
}
