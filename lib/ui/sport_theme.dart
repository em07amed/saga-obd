import 'package:flutter/material.dart';

/// Marker extension: present only in the sport theme, so widgets can switch
/// to segmented gauges and bold italic numbers.
class SportStyle extends ThemeExtension<SportStyle> {
  const SportStyle();

  @override
  SportStyle copyWith() => this;

  @override
  SportStyle lerp(ThemeExtension<SportStyle>? other, double t) => this;
}

bool isSport(BuildContext context) =>
    Theme.of(context).extension<SportStyle>() != null;

/// Pure black with a glowing amber accent, matching the app icon.
const sportAccent = Color(0xFFFF9904);
const sportAccentHot = Color(0xFFFFE55D);

ThemeData sportTheme() {
  const accent = sportAccent;
  const bg = Color(0xFF000000);
  const card = Color(0xFF0E0E0F);
  const line = Color(0xFF1F1F22);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    onPrimary: Colors.black,
    primaryContainer: const Color(0xFF2A1A02),
    onPrimaryContainer: const Color(0xFFFFC870),
    secondary: sportAccentHot,
    onSecondary: Colors.black,
    surface: bg,
    onSurface: const Color(0xFFF5F5F5),
    onSurfaceVariant: const Color(0xFF9A9A9F),
    surfaceContainerHighest: const Color(0xFF121213),
    surfaceContainerHigh: const Color(0xFF101011),
    surfaceContainer: const Color(0xFF0C0C0D),
    outline: const Color(0xFF3A3A3E),
    outlineVariant: line,
    error: const Color(0xFFFF453A),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Color(0xFFF5F5F5),
    ),
    cardTheme: const CardThemeData(
      color: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: line),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.black,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          backgroundColor: accent, foregroundColor: Colors.black),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.black : null),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : null),
    ),
    dividerTheme: const DividerThemeData(color: line),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? accent
              : const Color(0xFF8A8A90))),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? accent
              : const Color(0xFF8A8A90))),
    ),
    extensions: const [SportStyle()],
  );
}
