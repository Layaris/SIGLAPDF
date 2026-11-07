import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Temi chiaro e scuro: font di sistema, pochi bordi, niente ombre decorative.
class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.accent,
      onPrimary: b == Brightness.light ? Colors.white : const Color(0xFF0B1230),
      secondary: c.ink,
      onSecondary: c.surface,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.secondary,
      outline: c.line,
      outlineVariant: c.line,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.paper,
      surfaceContainerHigh: c.paper,
      surfaceContainerHighest: c.line,
      tertiary: c.success,
      onTertiary: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: c.paper,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink);
    const radius = BorderRadius.all(Radius.circular(12));

    return base.copyWith(
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        // Dimensione esplicita: nel tema base i TextStyle non hanno ancora le misure.
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink, letterSpacing: -0.4),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.12),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.ink)),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.accent : c.secondary),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.secondary),
        selectedLabelTextStyle: TextStyle(fontSize: 13, color: c.ink, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(fontSize: 13, color: c.secondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: c.ink,
          side: BorderSide(color: c.line),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: c.accent),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.line)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.line)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.accent, width: 1.5)),
        labelStyle: TextStyle(color: c.secondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.secondary,
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: c.line),
        backgroundColor: c.surface,
        selectedColor: c.accent.withValues(alpha: 0.12),
        labelStyle: TextStyle(fontSize: 14, color: c.ink),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: TextStyle(color: c.paper),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      sliderTheme: base.sliderTheme.copyWith(activeTrackColor: c.accent, thumbColor: c.accent),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : null),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: c.line),
          selectedBackgroundColor: c.accent.withValues(alpha: 0.12),
          selectedForegroundColor: c.accent,
        ),
      ),
    );
  }
}
