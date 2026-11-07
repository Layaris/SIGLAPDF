import 'package:flutter/material.dart';

/// Palette "inchiostro e carta".
class AppColors {
  const AppColors._({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.accent,
    required this.secondary,
    required this.line,
    required this.success,
    required this.danger,
  });

  final Color paper;
  final Color surface;
  final Color ink;
  final Color accent;
  final Color secondary;
  final Color line;
  final Color success;
  final Color danger;

  static const light = AppColors._(
    paper: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF1B2A4A),
    accent: Color(0xFF2347D9),
    secondary: Color(0xFF6B7280),
    line: Color(0xFFE3E6EB),
    success: Color(0xFF1F8A5B),
    danger: Color(0xFFB42318),
  );

  static const dark = AppColors._(
    paper: Color(0xFF0F1420),
    surface: Color(0xFF171D2B),
    ink: Color(0xFFE6EAF2),
    accent: Color(0xFF8FA4FF),
    secondary: Color(0xFF9AA3B2),
    line: Color(0xFF283044),
    success: Color(0xFF4CC48C),
    danger: Color(0xFFF97066),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Colori dell'inchiostro disponibili per firme e testi sul PDF.
class InkColors {
  static const blue = Color(0xFF1D3FBF);
  static const black = Color(0xFF111111);

  static Color fromName(String name) => name == 'black' ? black : blue;
  static String nameOf(Color c) => c.toARGB32() == black.toARGB32() ? 'black' : 'blue';
}
