import 'dart:math' as math;
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

  /// Relleno del cristal: más claro en modo claro, apenas velado en modo oscuro.
  Color get glass => dark ? const Color(0x24FFFFFF) : const Color(0x8CFFFFFF);
  Color get glassStrong => dark ? const Color(0x4D1C1C2E) : const Color(0xC7FFFFFF);
  Color get glassEdge => dark ? const Color(0x47FFFFFF) : const Color(0xCCFFFFFF);

  static Pal of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? _dark : _light;
}

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal._dark : Pal._light;
  return ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AC.blue, brightness: b).copyWith(primary: AC.blue, surface: p.card),
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
      foregroundColor: p.label, titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.label),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0),
    snackBarTheme: const SnackBarThemeData(backgroundColor: Colors.transparent, elevation: 0, behavior: SnackBarBehavior.floating),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: p.separator,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: b == Brightness.dark ? const Color(0x24FFFFFF) : const Color(0x66FFFFFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          backgroundColor: AC.blue.withOpacity(0.9),
          side: const BorderSide(color: Color(0x59FFFFFF), width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: b == Brightness.dark ? const Color(0x1AFFFFFF) : const Color(0x66FFFFFF),
        side: BorderSide(color: p.glassEdge, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

/// Fondo "aurora": manchas de color suaves y en movimiento lento. El cristal las desenfoca y refracta;
/// cambia de paleta con el modo claro/oscuro, así todo el vidrio se adapta solo.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});
  final Widget child;
  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: CustomPaint(painter: _AuroraPainter(_c, dark))),
      widget.child,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t, this.dark) : super(repaint: t);
  final Animation<double> t;
  final bool dark;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF05060F), Color(0xFF0B1030)] : const [Color(0xFFE6EEFF), Color(0xFFF7EEFF)],
        ).createShader(rect),
    );
    final a = t.value * 2 * math.pi;
    final blobs = <(double, double, double, Color, double)>[
      (0.15 + 0.10 * math.sin(a), 0.12 + 0.06 * math.cos(a), 0.60, AC.blue, dark ? 0.55 : 0.50),
      (0.90 + 0.06 * math.cos(a * 1), 0.35 + 0.08 * math.sin(a + 1), 0.55, AC.purple, dark ? 0.45 : 0.40),
      (0.20 + 0.08 * math.cos(a + 2), 0.70 + 0.07 * math.sin(a), 0.55, AC.teal, dark ? 0.38 : 0.45),
      (0.85 + 0.05 * math.sin(a + 3), 0.92 + 0.04 * math.cos(a + 1), 0.50, AC.pink, dark ? 0.32 : 0.32),
    ];
    for (final b in blobs) {
      final c = Offset(s.width * b.$1, s.height * b.$2);
      final r = s.longestSide * b.$3 * 0.5;
      canvas.drawCircle(
        c, r,
        Paint()..shader = RadialGradient(colors: [b.$4.withOpacity(b.$5), b.$4.withOpacity(0)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter o) => o.dark != dark;
}
