import 'dart:math';
import 'package:flutter/material.dart';
import '../track/track_state.dart';
import 'theme.dart';

/// Mapa dibujado en el teléfono: funciona sin internet ni teselas. Muestra el recorrido, lugares de la
/// comunidad y alertas cercanas respecto a un centro; no es un mapa de calles, sino de "dónde estoy y qué hay cerca".
class MapView extends StatelessWidget {
  const MapView({super.key, required this.track, this.me, this.places = const [], this.alerts = const [], this.height = 280, this.onPlaceTap});
  final List<List<double>> track;
  final List<double>? me; // [lat, lon]
  final List<Map<String, dynamic>> places, alerts;
  final double height;
  final void Function(Map<String, dynamic>)? onPlaceTap;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return LayoutBuilder(builder: (c, box) {
      final painter = _MapPainter(track, me, places, alerts, p);
      return GestureDetector(
        onTapUp: onPlaceTap == null ? null : (d) {
          final hit = painter.hit(d.localPosition, Size(box.maxWidth, height));
          if (hit != null) onPlaceTap!(hit);
        },
        child: ClipRRect(borderRadius: BorderRadius.circular(18), child: SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: painter))),
      );
    });
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.track, this.me, this.places, this.alerts, this.pal);
  final List<List<double>> track;
  final List<double>? me;
  final List<Map<String, dynamic>> places, alerts;
  final Pal pal;

  // Proyección local (metros alrededor del centro): suficiente para escalas de barrio.
  late final List<List<double>> _pts = [
    for (final t in track) [t[0], t[1]],
    if (me != null) me!,
    for (final a in alerts) [(a['lat'] as num).toDouble(), (a['lon'] as num).toDouble()],
  ];

  late final double _cLat = _pts.isEmpty ? 0 : _pts.map((e) => e[0]).reduce((a, b) => a + b) / _pts.length;
  late final double _cLon = _pts.isEmpty ? 0 : _pts.map((e) => e[1]).reduce((a, b) => a + b) / _pts.length;

  Offset _m(double lat, double lon) => Offset((lon - _cLon) * 111320 * cos(_cLat * pi / 180), -(lat - _cLat) * 111320);

  late final double _span = () {
    var m = 150.0; // mínimo ~300 m de ancho
    for (final q in _pts) {
      final o = _m(q[0], q[1]);
      m = max(m, max(o.dx.abs(), o.dy.abs()) * 1.25);
    }
    return m;
  }();

  Offset _px(double lat, double lon, Size s) {
    final o = _m(lat, lon);
    final k = min(s.width, s.height) / (2 * _span);
    return Offset(s.width / 2 + o.dx * k, s.height / 2 + o.dy * k);
  }

  List<(Map<String, dynamic>, Offset)> _marks(Size s) => [
        for (final pl in places) (pl, _px((pl['lat'] as num).toDouble(), (pl['lon'] as num).toDouble(), s)),
      ];

  Map<String, dynamic>? hit(Offset tap, Size s) {
    for (final (pl, o) in _marks(s)) {
      if ((o - tap).distance < 22) return pl;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = pal.card);
    final grid = Paint()..color = pal.separator.withOpacity(0.5)..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(Offset(s.width * i / 6, 0), Offset(s.width * i / 6, s.height), grid);
      canvas.drawLine(Offset(0, s.height * i / 6), Offset(s.width, s.height * i / 6), grid);
    }
    // Recorrido
    if (track.length > 1) {
      final path = Path();
      for (var i = 0; i < track.length; i++) {
        final o = _px(track[i][0], track[i][1], s);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, Paint()..color = AC.blue.withOpacity(0.25)..style = PaintingStyle.stroke..strokeWidth = 9..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
      canvas.drawPath(path, Paint()..color = AC.blue..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
      final a = _px(track.first[0], track.first[1], s);
      canvas.drawCircle(a, 6, Paint()..color = AC.green);
      canvas.drawCircle(a, 6, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    // Lugares de la comunidad
    for (final (pl, o) in _marks(s)) {
      if (o.dx < -10 || o.dy < -10 || o.dx > s.width + 10 || o.dy > s.height + 10) continue;
      final col = Color((placeKinds[pl['kind']] ?? placeKinds['other']!).$2);
      canvas.drawCircle(o, 11, Paint()..color = col.withOpacity(0.25));
      canvas.drawCircle(o, 6.5, Paint()..color = col);
      canvas.drawCircle(o, 6.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    // Alertas SOS
    for (final a in alerts) {
      final o = _px((a['lat'] as num).toDouble(), (a['lon'] as num).toDouble(), s);
      canvas.drawCircle(o, 18, Paint()..color = AC.red.withOpacity(0.25));
      canvas.drawCircle(o, 9, Paint()..color = AC.red);
      canvas.drawCircle(o, 9, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }
    // Yo
    if (me != null) {
      final o = _px(me![0], me![1], s);
      canvas.drawCircle(o, 16, Paint()..color = AC.blue.withOpacity(0.2));
      canvas.drawCircle(o, 7, Paint()..color = AC.blue);
      canvas.drawCircle(o, 7, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
    }
    // Escala
    final k = min(s.width, s.height) / (2 * _span);
    final nice = [20, 50, 100, 200, 500, 1000, 2000].lastWhere((m) => m * k <= s.width * 0.35, orElse: () => 20);
    final y = s.height - 14;
    final sp = Paint()..color = pal.secondary..strokeWidth = 2;
    canvas.drawLine(Offset(14, y), Offset(14 + nice * k, y), sp);
    final tp = TextPainter(text: TextSpan(text: nice >= 1000 ? '${nice ~/ 1000} km' : '$nice m', style: TextStyle(color: pal.secondary, fontSize: 11)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(14, y - 16));
    final n = TextPainter(text: TextSpan(text: 'N ↑', style: TextStyle(color: pal.secondary, fontSize: 11, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
    n.paint(canvas, Offset(s.width - 30, 8));
  }

  @override
  bool shouldRepaint(covariant _MapPainter o) => true;
}
