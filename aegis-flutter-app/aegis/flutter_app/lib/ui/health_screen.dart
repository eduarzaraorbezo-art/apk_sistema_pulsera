import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../health/reading.dart';
import 'charts.dart';
import 'goals_section.dart';
import 'theme.dart';
import 'widgets.dart';

enum Range { live, h1, h24, d7 }

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});
  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  Range _r = Range.live;
  Future<List<Reading>>? _future;

  Duration get _dur => switch (_r) { Range.h1 => const Duration(hours: 1), Range.h24 => const Duration(hours: 24), Range.d7 => const Duration(days: 7), _ => const Duration(minutes: 10) };

  void _load() => _future = context.read<AppState>().loadRange(_dur);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(_load); });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final hr = s.latest?.hr;
    return Page2(
      title: 'Salud',
      subtitle: s.bandConnected ? 'Datos de tu pulsera' : (s.demo ? 'Datos simulados' : 'Sin pulsera conectada'),
      children: [
        Segmented<Range>(
          value: _r,
          items: const {Range.live: 'En vivo', Range.h1: '1 h', Range.h24: '24 h', Range.d7: '7 días'},
          onChanged: (v) => setState(() { _r = v; _load(); }),
        ),
        const SizedBox(height: 14),
        Card2(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PulsingHeart(bpm: hr, size: 22),
              const SizedBox(width: 8),
              const Text('Pulsaciones', style: TextStyle(color: AC.red, fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              Text(hr == null ? '--' : '$hr', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: p.label)),
              Text(' lpm', style: TextStyle(color: p.secondary)),
            ]),
            const SizedBox(height: 10),
            if (_r == Range.live)
              HrChart(data: s.live, hrMin: s.hrMin, hrMax: s.hrMax)
            else
              FutureBuilder<List<Reading>>(
                future: _future,
                builder: (_, snap) => HrChart(data: snap.data ?? const [], hrMin: s.hrMin, hrMax: s.hrMax),
              ),
          ]),
        ),
        _Stats(range: _r, future: _future, live: s.live, s: s),
        const SizedBox(height: 4),
        const SectionLabel('Ahora'),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9,
          children: [
            StatTile(icon: CupertinoIcons.drop_fill, color: AC.teal, label: 'Oxígeno (SpO₂)', value: s.latest?.spo2?.toString() ?? '--', unit: '%'),
            StatTile(icon: CupertinoIcons.thermometer, color: AC.orange, label: 'Temperatura', value: s.latest?.tempC?.toStringAsFixed(1) ?? '--', unit: '°C'),
            StatTile(icon: CupertinoIcons.person_2_fill, color: AC.green, label: 'Pasos', value: s.latest?.steps?.toString() ?? '--'),
            StatTile(icon: Icons.battery_full, color: AC.blue, label: 'Batería pulsera', value: s.latest?.battery?.toString() ?? '--', unit: '%'),
          ],
        ),
        const SizedBox(height: 12),
        const GoalsSection(),
        const SectionLabel('Alertas de pulsaciones'),
        Group(children: [
          Row2(
            icon: CupertinoIcons.bell_fill, color: AC.orange, title: 'Rango normal',
            value: '${s.hrMin}–${s.hrMax} lpm', chevron: true, onTap: () => s.setTab(4),
            subtitle: 'Avisa tras 3 lecturas seguidas fuera de rango',
          ),
          Row2(
            icon: CupertinoIcons.waveform_path_ecg, color: AC.red, title: 'Modo demostración',
            subtitle: 'Simula una pulsera para probar la app',
            trailing: Switch.adaptive(value: s.demo, onChanged: s.bandConnected ? null : s.setDemo),
          ),
          if (s.demo)
            Row2(icon: CupertinoIcons.bolt_fill, color: AC.pink, title: 'Simular pico de pulsaciones', chevron: true, onTap: s.simulateSpike),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'AEGIS no es un dispositivo médico: las mediciones son orientativas. Ante dolor en el pecho, mareo o falta de aire, llama al 105 o al 106.',
            style: TextStyle(fontSize: 12, color: p.secondary),
          ),
        ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.range, required this.future, required this.live, required this.s});
  final Range range;
  final Future<List<Reading>>? future;
  final List<Reading> live;
  final AppState s;

  Widget _row(BuildContext c, List<Reading> d) {
    final hrs = [for (final r in d) if (r.hr != null) r.hr!];
    final p = Pal.of(c);
    Widget cell(String label, String v, Color col) => Expanded(
          child: Column(children: [
            Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: col)),
            Text(label, style: TextStyle(fontSize: 12, color: p.secondary)),
          ]),
        );
    final alerts = d.where((r) => r.hr != null && (r.hr! < s.hrMin || r.hr! > s.hrMax)).length;
    return Card2(
      child: Row(children: [
        cell('Mínima', hrs.isEmpty ? '--' : '${hrs.reduce((a, b) => a < b ? a : b)}', AC.teal),
        cell('Promedio', hrs.isEmpty ? '--' : '${(hrs.reduce((a, b) => a + b) / hrs.length).round()}', p.label),
        cell('Máxima', hrs.isEmpty ? '--' : '${hrs.reduce((a, b) => a > b ? a : b)}', AC.red),
        cell('Fuera de rango', '$alerts', alerts > 0 ? AC.orange : AC.green),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (range == Range.live) return _row(context, live);
    return FutureBuilder<List<Reading>>(future: future, builder: (c, snap) => _row(c, snap.data ?? const []));
  }
}
