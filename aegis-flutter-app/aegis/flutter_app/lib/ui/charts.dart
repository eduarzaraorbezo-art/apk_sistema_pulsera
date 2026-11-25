import 'dart:math';
import 'package:flutter/material.dart';
import '../health/reading.dart';
import 'theme.dart';

/// Gráfica de frecuencia cardíaca con área degradada, umbrales y último punto.
class HrChart extends StatelessWidget {
  const HrChart({super.key, required this.data, required this.hrMin, required this.hrMax, this.height = 180});
  final List<Reading> data;
  final int hrMin, hrMax;
  final double height;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _HrPainter([for (final r in data) if (r.hr != null) r], hrMin, hrMax, p)),
    );
  }
}

class _HrPainter extends CustomPainter {
  _HrPainter(this.d, this.lo, this.hi, this.p);
  final List<Reading> d;
  final int lo, hi;
  final Pal p;

  @override
  void paint(Canvas canvas, Size s) {
    const left = 30.0, bottom = 18.0;
    final w = s.width - left, h = s.height - bottom;
    final maxV = max(160, d.isEmpty ? 0 : d.map((r) => r.hr!).reduce(max) + 10).toDouble();
    const minV = 40.0;
    double y(num v) => h - (v - minV) / (maxV - minV) * h;

    final grid = Paint()..color = p.separator..strokeWidth = 0.5;
    for (final v in [60, 100, 140]) {
      canvas.drawLine(Offset(left, y(v)), Offset(s.width, y(v)), grid);
      _text(canvas, '$v', Offset(0, y(v) - 6), p.secondary, 10);
    }
    // umbrales
    final dash = Paint()..color = AC.orange.withOpacity(0.7)..strokeWidth = 1;
    for (final v in [lo, hi]) {
      if (v < minV || v > maxV) continue;
      for (double x = left; x < s.width; x += 8) {
        canvas.drawLine(Offset(x, y(v)), Offset(min(x + 4, s.width), y(v)), dash);
      }
    }
    if (d.length < 2) {
      _text(canvas, d.isEmpty ? 'Sin datos todavía' : 'Recibiendo datos…', Offset(left + w / 2 - 50, h / 2 - 8), p.secondary, 14);
      return;
    }
    final t0 = d.first.ts, t1 = d.last.ts;
    final span = max(1, t1 - t0);
    final pts = [for (final r in d) Offset(left + (r.ts - t0) / span * w, y(r.hr!))];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final mid = Offset((pts[i - 1].dx + pts[i].dx) / 2, (pts[i - 1].dy + pts[i].dy) / 2);
      line.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
    }
    line.lineTo(pts.last.dx, pts.last.dy);
    final fill = Path.from(line)..lineTo(pts.last.dx, h)..lineTo(pts.first.dx, h)..close();
    canvas.drawPath(
        fill,
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AC.red.withOpacity(0.35), AC.red.withOpacity(0)]).createShader(Rect.fromLTWH(left, 0, w, h)));
    canvas.drawPath(line, Paint()..color = AC.red..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
    canvas.drawCircle(pts.last, 6, Paint()..color = AC.red.withOpacity(0.25));
    canvas.drawCircle(pts.last, 3.5, Paint()..color = AC.red);
    _text(canvas, _clock(t0), Offset(left, h + 4), p.secondary, 10);
    _text(canvas, _clock(t1), Offset(s.width - 30, h + 4), p.secondary, 10);
  }

  String _clock(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _text(Canvas c, String t, Offset o, Color col, double size) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: col, fontSize: size)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant _HrPainter o) => true;
}

/// Mini gráfica sin ejes.
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.color = AC.red, this.height = 44});
  final List<int> values;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values, color)));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.c);
  final List<int> v;
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    if (v.length < 2) return;
    final lo = v.reduce(min).toDouble(), hi = max(v.reduce(max).toDouble(), lo + 10);
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final o = Offset(i / (v.length - 1) * s.width, s.height - (v[i] - lo) / (hi - lo) * (s.height - 4) - 2);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter o) => true;
}

/// Corazón que late al ritmo de [bpm].
class PulsingHeart extends StatefulWidget {
  const PulsingHeart({super.key, required this.bpm, this.size = 28, this.color = AC.red});
  final int? bpm;
  final double size;
  final Color color;
  @override
  State<PulsingHeart> createState() => _PulsingHeartState();
}

class _PulsingHeartState extends State<PulsingHeart> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _dur(widget.bpm))..repeat(reverse: true);
  Duration _dur(int? b) => Duration(milliseconds: (30000 / (b == null || b < 30 ? 70 : b)).round().clamp(120, 1000).toInt());

  @override
  void didUpdateWidget(covariant PulsingHeart old) {
    super.didUpdateWidget(old);
    if (old.bpm != widget.bpm) {
      _c.duration = _dur(widget.bpm);
      if (!_c.isAnimating) _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.scale(
          scale: widget.bpm == null ? 1 : 1 + 0.2 * Curves.easeOut.transform(_c.value),
          child: Icon(Icons.favorite, color: widget.color, size: widget.size),
        ),
      );
}

/// Botón SOS: hay que mantenerlo pulsado hasta completar el anillo (evita toques accidentales).
class SosHoldButton extends StatefulWidget {
  const SosHoldButton({super.key, required this.onTriggered, this.holdMs = 1500});
  final VoidCallback onTriggered;
  final int holdMs;
  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.holdMs))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onTriggered();
        _c.value = 0;
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() => _c.forward();
  void _up() {
    if (_c.status != AnimationStatus.completed) _c.reverse();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => SizedBox(
            width: 190, height: 190,
            child: CustomPaint(
              painter: _RingPainter(_c.value),
              child: Center(
                child: Transform.scale(
                  scale: 1 - 0.05 * _c.value,
                  child: Container(
                    width: 156, height: 156,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF6A5E), Color(0xFFE0261B)]),
                      boxShadow: [BoxShadow(color: AC.red.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('SOS', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      Text('Mantén pulsado', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width / 2 - 5);
    c.drawCircle(r.center, r.width / 2, Paint()..color = AC.red.withOpacity(0.15)..style = PaintingStyle.stroke..strokeWidth = 8);
    c.drawArc(r, -pi / 2, 2 * pi * t, false, Paint()..color = AC.red..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.t != t;
}

/// Anillo de progreso con contenido (cuenta atrás del check-in).
class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.progress, required this.child, this.color = AC.blue, this.size = 170});
  final double progress; // 0..1
  final Widget child;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size, height: size,
        child: CustomPaint(painter: _CountPainter(progress.clamp(0.0, 1.0).toDouble(), color, Pal.of(context).fill), child: Center(child: child)),
      );
}

class _CountPainter extends CustomPainter {
  _CountPainter(this.t, this.c, this.bg);
  final double t;
  final Color c, bg;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width / 2 - 7);
    canvas.drawCircle(r.center, r.width / 2, Paint()..color = bg..style = PaintingStyle.stroke..strokeWidth = 10);
    canvas.drawArc(r, -pi / 2, 2 * pi * t, false, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _CountPainter o) => o.t != t || o.c != c;
}
