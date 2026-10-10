import 'package:flutter/material.dart';

/// Colour tokens as a ThemeExtension so every widget reads `MgColors.of(context)`.
@immutable
class MgColors extends ThemeExtension<MgColors> {
  const MgColors({
    required this.ink900,
    required this.ink800,
    required this.ink700,
    required this.ink600,
    required this.slate500,
    required this.slate400,
    required this.slate300,
    required this.slate200,
    required this.slate100,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.text,
    required this.muted,
    required this.border,
    required this.amber500,
    required this.amber600,
    required this.amber50,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.crisis,
    required this.info,
    required this.infoBg,
    required this.positionBlue,
  });

  final Color ink900, ink800, ink700, ink600;
  final Color slate500, slate400, slate300, slate200, slate100;
  final Color bg, surface, surfaceRaised, text, muted, border;
  final Color amber500, amber600, amber50;
  final Color success, successBg, warning, warningBg, danger, dangerBg, crisis, info, infoBg;

  /// "You are here" on maps.
  final Color positionBlue;

  static const light = MgColors(
    ink900: Color(0xFF0B1220),
    ink800: Color(0xFF111A2E),
    ink700: Color(0xFF1C2740),
    ink600: Color(0xFF2A3754),
    slate500: Color(0xFF64748B),
    slate400: Color(0xFF94A3B8),
    slate300: Color(0xFFCBD5E1),
    slate200: Color(0xFFE2E8F0),
    slate100: Color(0xFFF1F5F9),
    bg: Color(0xFFF6F8FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    text: Color(0xFF0B1220),
    muted: Color(0xFF64748B),
    border: Color(0xFFE2E8F0),
    amber500: Color(0xFFF59E0B),
    amber600: Color(0xFFD97706),
    amber50: Color(0xFFFFF7E6),
    success: Color(0xFF16A34A),
    successBg: Color(0xFFECFDF3),
    warning: Color(0xFFD97706),
    warningBg: Color(0xFFFFF7E6),
    danger: Color(0xFFDC2626),
    dangerBg: Color(0xFFFEF2F2),
    crisis: Color(0xFF7F1D1D),
    info: Color(0xFF0E7490),
    infoBg: Color(0xFFECFEFF),
    positionBlue: Color(0xFF2563EB),
  );

  static const dark = MgColors(
    ink900: Color(0xFF0B1220),
    ink800: Color(0xFF111A2E),
    ink700: Color(0xFF1C2740),
    ink600: Color(0xFF2A3754),
    slate500: Color(0xFF64748B),
    slate400: Color(0xFF94A3B8),
    slate300: Color(0xFFCBD5E1),
    slate200: Color(0xFFE2E8F0),
    slate100: Color(0xFFF1F5F9),
    bg: Color(0xFF0B1220),
    surface: Color(0xFF111A2E),
    surfaceRaised: Color(0xFF1C2740),
    text: Color(0xFFE2E8F0),
    muted: Color(0xFF94A3B8),
    border: Color(0xFF2A3754),
    amber500: Color(0xFFF59E0B),
    amber600: Color(0xFFF59E0B),
    amber50: Color(0xFF2A2210),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF0F2A1B),
    warning: Color(0xFFFBBF24),
    warningBg: Color(0xFF2A2210),
    danger: Color(0xFFF87171),
    dangerBg: Color(0xFF2E1517),
    crisis: Color(0xFFB91C1C),
    info: Color(0xFF22D3EE),
    infoBg: Color(0xFF0D2A33),
    positionBlue: Color(0xFF60A5FA),
  );

  static MgColors of(BuildContext context) => Theme.of(context).extension<MgColors>() ?? light;

  @override
  MgColors copyWith() => this;

  @override
  MgColors lerp(ThemeExtension<MgColors>? other, double t) => t < 0.5 ? this : (other as MgColors? ?? this);
}

/// 4-point spacing grid.
class Space {
  Space._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double x2 = 24;
  static const double x3 = 32;
  static const double x4 = 48;
}

class Radii {
  Radii._();
  static const double sm = 8;
  static const double card = 12;
  static const double sheet = 20;
  static const double pill = 999;
}

class Widths {
  Widths._();
  static const double form = 440;
  static const double page = 1200;
}

class Shadows {
  Shadows._();
  static List<BoxShadow> level(int n, {bool dark = false}) {
    final a = dark ? 0.5 : 0.08;
    switch (n) {
      case 1:
        return [BoxShadow(color: Colors.black.withValues(alpha: a * 0.6), blurRadius: 4, offset: const Offset(0, 1))];
      case 2:
        return [BoxShadow(color: Colors.black.withValues(alpha: a), blurRadius: 12, offset: const Offset(0, 4))];
      default:
        return [BoxShadow(color: Colors.black.withValues(alpha: a * 1.6), blurRadius: 28, offset: const Offset(0, 12))];
    }
  }
}
