import 'package:flutter/material.dart';

/// Colores de sistema al estilo iOS.
class AC {
  static const blue = Color(0xFF0A84FF);
  static const red = Color(0xFFFF3B30);
  static const green = Color(0xFF30D158);
  static const orange = Color(0xFFFF9F0A);
  static const pink = Color(0xFFFF375F);
  static const purple = Color(0xFFBF5AF2);
  static const teal = Color(0xFF40C8E0);
  static const gray = Color(0xFF8E8E93);
}

/// Paleta que cambia con el modo claro/oscuro.
class Pal {
  final Color bg, card, label, secondary, separator, fill;
  final bool dark;
  const Pal._(this.bg, this.card, this.label, this.secondary, this.separator, this.fill, this.dark);

  static const _light = Pal._(Color(0xFFF2F2F7), Colors.white, Color(0xFF000000), Color(0xFF6C6C70), Color(0x1F000000), Color(0x14787880), false);
  static const _dark = Pal._(Color(0xFF000000), Color(0xFF1C1C1E), Color(0xFFFFFFFF), Color(0xFF98989F), Color(0x33FFFFFF), Color(0x3D787880), true);

  static Pal of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? _dark : _light;
}

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal._dark : Pal._light;
  return ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AC.blue, brightness: b).copyWith(primary: AC.blue, surface: p.card),
    scaffoldBackgroundColor: p.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: p.separator,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.fill,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
    ),
  );
}
