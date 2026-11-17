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

/// Carbon black with a racing orange-red accent.
ThemeData sportTheme() {
  const accent = Color(0xFFFF4D1A);
  const bg = Color(0xFF0B0B0E);
  const card = Color(0xFF141519);
  const line = Color(0xFF26272D);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFF3A1208),
    onPrimaryContainer: const Color(0xFFFFB59E),
    secondary: const Color(0xFF00C8FF),
    surface: bg,
    onSurface: const Color(0xFFF2F2F4),
    onSurfaceVariant: const Color(0xFFA0A1AA),
    surfaceContainerHighest: const Color(0xFF1B1C21),
    outlineVariant: line,
    error: const Color(0xFFFF3B30),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    cardTheme: const CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0F1013),
      indicatorColor: accent.withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? accent
              : const Color(0xFFA0A1AA))),
    ),
    extensions: const [SportStyle()],
  );
}
