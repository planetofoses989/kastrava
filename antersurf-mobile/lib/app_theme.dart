import 'package:flutter/material.dart';

import 'services/settings_service.dart';

class AppTheme {
  static const Color darkBg = Color(0xFF06060C);
  static const Color darkSurface = Color(0xFF0A0A14);
  static const Color darkCard = Color(0xFF0E0E1A);
  static const Color darkBorder = Color(0xFF1A1A26);
  static const Color darkText = Color(0xFFE0E0EC);
  static const Color darkText2 = Color(0xFF8A8A9A);

  static const Color lightBg = Color(0xFFF6F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFEFEFF5);
  static const Color lightBorder = Color(0xFFE2E3EC);
  static const Color lightText = Color(0xFF1A1A24);
  static const Color lightText2 = Color(0xFF6A6A7A);

  static Color accentFrom(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 3) {
      h = h.split('').map((c) => '$c$c').join();
    }
    final v = int.tryParse(h, radix: 16) ?? 0x8AB4F8;
    return Color(0xFF000000 | v);
  }

  static bool isDark() => SettingsService.instance.settings.theme != 'light';

  static ColorScheme scheme() {
    final accent = accentFrom(SettingsService.instance.settings.accent);
    final dark = isDark();
    final bg = dark ? darkBg : lightBg;
    final surface = dark ? darkSurface : lightSurface;
    final card = dark ? darkCard : lightCard;
    final border = dark ? darkBorder : lightBorder;
    final text = dark ? darkText : lightText;
    final text2 = dark ? darkText2 : lightText2;
    return ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent.withValues(alpha: .8),
      onSecondary: Colors.white,
      error: const Color(0xFFE74C3C),
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      background: bg,
      onBackground: text,
      outline: border,
      outlineVariant: border,
      surfaceContainerHighest: card,
      surfaceContainer: card,
      surfaceContainerLow: card,
      surfaceContainerLowest: surface,
      surfaceContainerHigh: card,
      inverseSurface: text,
      onInverseSurface: bg,
      inversePrimary: accent,
      shadow: Colors.black,
      scrim: Colors.black,
      errorContainer: const Color(0x33E74C3C),
      onErrorContainer: const Color(0xFFE74C3C),
      primaryContainer: accent.withValues(alpha: .15),
      onPrimaryContainer: accent,
      secondaryContainer: accent.withValues(alpha: .12),
      onSecondaryContainer: accent,
      tertiary: accent,
      onTertiary: Colors.white,
      tertiaryContainer: accent.withValues(alpha: .12),
      onTertiaryContainer: accent,
    );
  }

  static ThemeData build() {
    final s = scheme();
    final radius = SettingsService.instance.settings.uiRadius == 'large'
        ? 18.0
        : SettingsService.instance.settings.uiRadius == 'small'
            ? 6.0
            : 12.0;
    return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      scaffoldBackgroundColor: s.background,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: s.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: s.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: s.onSurface),
      ),
      cardTheme: CardThemeData(
        color: s.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: s.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: s.primary, width: 1.5),
        ),
      ),
      dividerColor: s.outlineVariant,
      listTileTheme: ListTileThemeData(
        iconColor: s.onSurface,
        textColor: s.onSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? s.primary : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? s.primary.withValues(alpha: .4)
                : null),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: s.primary,
          foregroundColor: s.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }
}
