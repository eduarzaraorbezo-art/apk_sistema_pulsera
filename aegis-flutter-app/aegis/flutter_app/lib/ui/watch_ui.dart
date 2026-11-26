import 'dart:async';
import 'dart:math';
import 'dart:ui' show FontFeature;
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../ble/protocol.dart';
import '../health/reading.dart' show HrLevel;
import 'band_screen.dart';
import 'theme.dart';
import 'widgets.dart';

// Estilo "reloj inteligente": fondo oscuro tipo OLED, anillos de actividad, números redondeados grandes,
// Smart Stack deslizable y centro de control con botones de cristal.

const _ringPink = Color(0xFFFF2D55), _ringGreen = Color(0xFFA6FF00), _ringCyan = Color(0xFF00E5FF);

/// Tres anillos concéntricos con extremos redondeados y degradado, como los de Actividad.
class ActivityRings extends StatelessWidget {
  const ActivityRings({super.key, required this.values, this.size = 132, this.child});
  final List<double> values; // 3 valores 0..1
  final double size;
  final Widget? child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => SizedBox(
          width: size, height: size,
          child: CustomPaint(painter: _RingsPainter([for (final v in values) v.clamp(0, 1) * t]), child: Center(child: child)),
        ),
      );
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.v);
  final List<double> v;
  static const cols = [_ringPink, _ringGreen, _ringCyan];

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final stroke = s.width * 0.115;
    for (var i = 0; i < 3; i++) {
      final r = s.width / 2 - stroke / 2 - i * (stroke + 3);
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = cols[i].withOpacity(0.22));
      final sweep = max(0.001, v[i]) * 2 * pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(startAngle: -pi / 2, endAngle: -pi / 2 + max(0.2, sweep), colors: [cols[i].withOpacity(0.65), cols[i]], transform: const GradientRotation(0)).createShader(rect);
      canvas.drawArc(rect, -pi / 2, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter o) => o.v.length != v.length || [for (var i = 0; i < v.length; i++) o.v[i] != v[i]].contains(true);
}

/// Corazón que late al ritmo real de la pulsera.
class _Beat extends StatefulWidget {
  const _Beat({required this.bpm, this.size = 22});
  final int? bpm;
  final double size;
  @override
  State<_Beat> createState() => _BeatState();
}

class _BeatState extends State<_Beat> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _dur())..repeat(reverse: true);
  Duration _dur() => Duration(milliseconds: (30000 / (widget.bpm ?? 70).clamp(35, 200)).round());

  @override
  void didUpdateWidget(covariant _Beat o) {
    super.didUpdateWidget(o);
    if (o.bpm != widget.bpm) {
      _c.duration = _dur();
      _c.repeat(reverse: true);
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
        builder: (_, __) => Transform.scale(scale: 0.88 + 0.24 * Curves.easeInOut.transform(_c.value), child: Icon(CupertinoIcons.heart_fill, color: _ringPink, size: widget.size)),
      );
}

/// Esfera principal: hora, anillos y complicaciones de la pulsera.
class WatchFace extends StatefulWidget {
  const WatchFace(this.s, {super.key});
  final AppState s;
  @override
  State<WatchFace> createState() => _WatchFaceState();
}

class _WatchFaceState extends State<WatchFace> {
  Timer? _t;
  int _steps = 0;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSteps();
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _loadSteps();
    });
  }

  Future<void> _loadSteps() async {
    final n = await widget.s.todaySteps();
    if (mounted && n != _steps) setState(() => _steps = n);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  static const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final l = s.latest;
    final hr = l?.hr;
    final bat = l?.battery;
    final stepsV = s.stepGoal == 0 ? 0.0 : _steps / s.stepGoal;
    final shield = ((s.bandConnected || s.demo ? 1 : 0) + (s.trk.active ? 1 : 0) + (s.contacts.isNotEmpty ? 1 : 0)) / 3.0;
    final calm = hr == null ? 0.0 : (s.hrState == HrLevel.normal ? 1.0 : 0.45);
    final hh = _now.hour.toString().padLeft(2, '0'), mm = _now.minute.toString().padLeft(2, '0');
    final live = s.bandConnected || s.demo;
    return PressScale(
      onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const BandScreen())),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(44),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14141C), Color(0xFF05050A)]),
          border: Border.all(color: Colors.white.withOpacity(0.16), width: 1.4),
          boxShadow: [BoxShadow(color: (live ? _ringCyan : Colors.black).withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Column(children: [
          Row(children: [
            ActivityRings(values: [stepsV, shield, calm], size: 128, child: _Beat(bpm: hr, size: 24)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$hh:$mm', style: const TextStyle(fontSize: 52, height: 1, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.5, fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(height: 2),
                Text('${_dias[_now.weekday - 1]} ${_now.day} ${_meses[_now.month - 1]}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.6))),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(hr == null ? '--' : '$hr', style: const TextStyle(fontSize: 30, height: 1, fontWeight: FontWeight.w800, color: _ringPink)),
                  const SizedBox(width: 4),
                  Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('lpm', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ringPink.withOpacity(0.8)))),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _Legend(_ringPink, 'Pasos', '$_steps'),
            _Legend(_ringGreen, 'Escudo', '${(shield * 100).round()}%'),
            _Legend(_ringCyan, 'Calma', hr == null ? '—' : (calm == 1 ? 'OK' : 'Alta')),
            _Chip(live ? CupertinoIcons.bluetooth : CupertinoIcons.exclamationmark_triangle_fill, live ? (bat == null ? 'Activa' : '$bat%') : 'Sin conexión', live ? (bat != null && bat <= 20 ? AC.red : AC.green) : AC.gray),
          ]),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.c, this.label, this.value);
  final Color c;
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55)))]),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c)),
      ]);
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.45))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 5), Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))]),
      );
}

/// Smart Stack: tarjetas de sensores deslizables con números grandes.
class SmartStack extends StatelessWidget {
  const SmartStack(this.s, {super.key});
  final AppState s;

  static const _gName = {'sos_double': 'SOS · 2 toques', 'sos_triple': 'SOS · 3 toques', 'aux_short': 'Aux · 1 toque', 'aux_double': 'Aux · 2 toques', 'aux_hold': 'Aux · mantener'};
  static const _aName = {'message': 'Mensaje', 'share_location': 'Compartir ubicación', 'checkin_ok': 'Estoy bien', 'find_phone': 'Buscar teléfono', 'sos': 'SOS', 'none': 'Sin acción'};

  @override
  Widget build(BuildContext context) {
    final l = s.latest;
    final live = s.bandConnected || s.demo;
    String v(Object? x, [String suf = '']) => x == null || !live ? '--' : '$x$suf';
    final cards = <Widget>[
      _StackCard(icon: CupertinoIcons.heart_fill, color: _ringPink, title: 'Pulso', big: v(l?.hr), unit: 'lpm', foot: 'Rango ${s.hrMin}–${s.hrMax}'),
      _StackCard(icon: CupertinoIcons.drop_fill, color: _ringCyan, title: 'Oxígeno', big: v(l?.spo2), unit: '%', foot: 'SpO₂ en sangre'),
      _StackCard(icon: CupertinoIcons.thermometer, color: AC.orange, title: 'Temperatura', big: l?.tempC == null || !live ? '--' : l!.tempC!.toStringAsFixed(1), unit: '°C', foot: 'Piel de la muñeca'),
      _StackCard(
        icon: CupertinoIcons.hand_raised_fill, color: AC.purple, title: 'Gestos', big: '${(s.settings['gestures'] as Map).length}', unit: 'activos',
        foot: 'Toca para configurar', onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const BandScreen())),
        extra: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in _gName.entries.take(3))
            Text('${e.value} → ${_aName[s.gestureCfg(e.key)['action']] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.7))),
        ]),
      ),
      _StackCard(
        icon: CupertinoIcons.mic_fill, color: AC.green, title: 'Audio y cámara', big: s.rec.active ? 'REC' : 'Listo', unit: '', foot: s.canAutoRecord ? 'Se activan solos en un SOS' : 'Premium: grabación automática',
      ),
    ];
    return SizedBox(
      height: 168,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.8),
        padEnds: false,
        physics: const BouncingScrollPhysics(),
        itemCount: cards.length,
        itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(right: 10), child: cards[i]),
      ),
    );
  }
}

class _StackCard extends StatelessWidget {
  const _StackCard({required this.icon, required this.color, required this.title, required this.big, required this.unit, required this.foot, this.extra, this.onTap});
  final IconData icon;
  final Color color;
  final String title, big, unit, foot;
  final Widget? extra;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withOpacity(0.30), const Color(0xFF0B0B12)]),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 6), Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color))]),
            const Spacer(),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(big, style: const TextStyle(fontSize: 44, height: 1, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
              const SizedBox(width: 5),
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(unit, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.6)))),
            ]),
            const SizedBox(height: 6),
            extra ?? Text(foot, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
          ]),
        ),
      );
}

/// Centro de control: manda órdenes directas a la pulsera.
class BandControls extends StatelessWidget {
  const BandControls(this.s, {super.key});
  final AppState s;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          runSpacing: 10,
          children: [
            RoundBtn(icon: CupertinoIcons.bell_fill, label: 'Hacer sonar', color: AC.orange, onTap: s.ringBand),
            RoundBtn(icon: CupertinoIcons.waveform, label: 'Vibrar', color: AC.purple, onTap: () => s.bandCommand(Proto.cmdVibrate, arg: 2, ok: 'La pulsera vibra')),
            RoundBtn(icon: CupertinoIcons.camera_fill, label: 'Foto', color: AC.teal, onTap: () => s.bandCommand(Proto.cmdSnapshot, ok: 'Foto pedida a la pulsera')),
            RoundBtn(
              icon: s.rec.active ? CupertinoIcons.stop_fill : CupertinoIcons.mic_fill,
              label: s.rec.active ? 'Parar audio' : 'Grabar audio',
              color: AC.red,
              onTap: () => s.bandCommand(s.rec.active ? Proto.cmdRecStop : Proto.cmdRecStart, ok: s.rec.active ? 'Grabación detenida' : 'Grabando en la pulsera'),
            ),
            RoundBtn(icon: CupertinoIcons.slider_horizontal_3, label: 'Ajustes', color: AC.blue, onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const BandScreen()))),
          ],
        ),
      );
}
