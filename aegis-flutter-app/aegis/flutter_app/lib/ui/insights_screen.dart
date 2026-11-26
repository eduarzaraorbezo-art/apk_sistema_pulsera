import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../data/db.dart';
import '../health/reading.dart';
import 'charts.dart';
import 'billing_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Resumen de bienestar y seguridad. Todos ven lo básico; Premium suma el informe semanal y tendencias de 7 días.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final Future<_Data> _f = _load();

  Future<_Data> _load() async {
    final s = context.read<AppState>();
    final now = DateTime.now();
    final week = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final rs = await AegisDb.readingsSince(week);
    final tracks = await AegisDb.tracks();
    var km = 0.0, routes = 0;
    for (final t in tracks) {
      if (((t['started'] as int?) ?? 0) >= week) {
        km += ((t['distance'] as num?) ?? 0) / 1000;
        routes++;
      }
    }
    final em = s.emergencies.where((e) => ((e['started_at'] as int?) ?? 0) >= week && e['status'] != 'CANCELLED').length;
    final hrs = [for (final r in rs) if (r.hr != null) r.hr!];
    final byDay = <String, int>{};
    for (final r in rs) {
      final d = DateTime.fromMillisecondsSinceEpoch(r.ts);
      final k = '${d.day}/${d.month}';
      if ((r.steps ?? 0) > (byDay[k] ?? 0)) byDay[k] = r.steps!;
    }
    return _Data(steps: await s.todaySteps(), km: km, routes: routes, emergencies: em, hrs: hrs, stepsByDay: byDay, readings: rs);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen')),
      body: FutureBuilder<_Data>(
        future: _f,
        builder: (c, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator.adaptive());
          final sleepH = s.sleep.isEmpty ? 0.0 : ((s.sleep.first['minutes'] as num?) ?? 0) / 60;
          final stepsP = (d.steps / s.stepGoal).clamp(0.0, 1.0).toDouble();
          final sleepP = (sleepH / s.sleepGoalH).clamp(0.0, 1.0).toDouble();
          final hrOk = d.hrs.isEmpty ? 1.0 : d.hrs.where((h) => h >= s.hrMin && h <= s.hrMax).length / d.hrs.length;
          final score = ((stepsP * 0.35 + sleepP * 0.35 + hrOk * 0.30) * 100).round();
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Card2(
                child: Row(children: [
                  CountdownRing(
                    progress: score / 100, size: 118, color: score >= 70 ? AC.green : (score >= 40 ? AC.orange : AC.red),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$score', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: p.label)),
                      Text('bienestar', style: TextStyle(fontSize: 12, color: p.secondary)),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Tu puntaje de hoy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.label)),
                      const SizedBox(height: 6),
                      Text('Combina tus pasos, tu sueño y que tu pulso esté en rango.', style: TextStyle(fontSize: 13, color: p.secondary)),
                    ]),
                  ),
                ]),
              ),
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.5,
                children: [
                  StatTile(icon: CupertinoIcons.person_2_fill, color: AC.green, label: 'Pasos hoy', value: '${d.steps}', unit: '/ ${s.stepGoal}'),
                  StatTile(icon: CupertinoIcons.moon_fill, color: AC.purple, label: 'Sueño', value: sleepH.toStringAsFixed(1), unit: 'h'),
                  StatTile(icon: CupertinoIcons.location_north_fill, color: AC.blue, label: 'Recorridos (7 d)', value: d.km.toStringAsFixed(1), unit: 'km'),
                  StatTile(icon: CupertinoIcons.exclamationmark_shield_fill, color: AC.red, label: 'Alertas (7 d)', value: '${d.emergencies}'),
                ],
              ),
              const SizedBox(height: 14),
              SectionLabel('Informe semanal', trailing: s.isPremium ? const Pill('PREMIUM', icon: CupertinoIcons.star_fill, color: AC.orange, filled: true) : null),
              if (!s.isPremium)
                const _Locked('Informe semanal de seguridad', 'Pulso promedio, mínimo y máximo, pasos por día, recorridos y alertas de los últimos 7 días, con tu pulso en una gráfica.')
              else ...[
                _Weekly(d, s),
                if (d.readings.length > 2)
                  Card2(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pulso · 7 días', style: TextStyle(fontWeight: FontWeight.w700, color: p.label)),
                    const SizedBox(height: 8),
                    HrChart(data: d.readings, hrMin: s.hrMin, hrMax: s.hrMax, height: 150),
                  ])),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Data {
  _Data({required this.steps, required this.km, required this.routes, required this.emergencies, required this.hrs, required this.stepsByDay, required this.readings});
  final int steps, routes, emergencies;
  final double km;
  final List<int> hrs;
  final Map<String, int> stepsByDay;
  final List<Reading> readings;
}

class _Weekly extends StatelessWidget {
  const _Weekly(this.d, this.s);
  final _Data d;
  final AppState s;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final hrs = d.hrs;
    final avg = hrs.isEmpty ? '--' : (hrs.reduce((a, b) => a + b) / hrs.length).round().toString();
    final mn = hrs.isEmpty ? '--' : hrs.reduce((a, b) => a < b ? a : b).toString();
    final mx = hrs.isEmpty ? '--' : hrs.reduce((a, b) => a > b ? a : b).toString();
    final days = d.stepsByDay.entries.toList();
    final top = days.isEmpty ? 1 : days.map((e) => e.value).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30).toInt();
    return Card2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _kv(p, 'Pulso medio', avg, 'lpm'), _kv(p, 'Mínimo', mn, 'lpm'), _kv(p, 'Máximo', mx, 'lpm'),
        ]),
        const SizedBox(height: 14),
        Text('Pasos por día', style: TextStyle(fontWeight: FontWeight.w700, color: p.label)),
        const SizedBox(height: 8),
        if (days.isEmpty)
          Text('Aún no hay datos de la pulsera esta semana.', style: TextStyle(color: p.secondary))
        else
          SizedBox(
            height: 90,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final e in days)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      height: 70 * (e.value / top), margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AC.green, AC.teal])),
                    ),
                    const SizedBox(height: 4),
                    Text(e.key, style: TextStyle(fontSize: 10, color: p.secondary)),
                  ]),
                ),
            ]),
          ),
        const SizedBox(height: 10),
        Text('${d.routes} recorridos · ${d.km.toStringAsFixed(1)} km · ${d.emergencies} alertas', style: TextStyle(fontSize: 13, color: p.secondary)),
      ]),
    );
  }

  Widget _kv(Pal p, String k, String v, String u) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(fontSize: 12, color: p.secondary)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(v, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(width: 3),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(u, style: TextStyle(fontSize: 12, color: p.secondary))),
          ]),
        ]),
      );
}

class _Locked extends StatelessWidget {
  const _Locked(this.title, this.text);
  final String title, text;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Card2(
      color: AC.orange.withOpacity(0.12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(CupertinoIcons.lock_fill, color: AC.orange),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: p.label)),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(fontSize: 13, color: p.secondary)),
            const SizedBox(height: 8),
            const Pill('Disponible en Premium', icon: CupertinoIcons.star_fill, color: AC.orange),
          ]),
        ),
      ]),
    );
  }
}

/// Tarjeta de comparación de planes (se usa desde Inicio).
class PlanCard extends StatelessWidget {
  const PlanCard({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    const perks = [
      (CupertinoIcons.mic_fill, 'Grabación automática de audio y video en una emergencia'),
      (CupertinoIcons.cloud_upload_fill, 'Evidencias guardadas en la nube (150 MB)'),
      (CupertinoIcons.chart_bar_alt_fill, 'Informe semanal de pulso, pasos y recorridos'),
      (CupertinoIcons.lock_shield_fill, 'Alertas silenciosas con PIN de coacción'),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.isPremium ? const [Color(0xFF7C3AED), Color(0xFF2563EB)] : const [Color(0xFFFF9F0A), Color(0xFFFF375F)]),
        boxShadow: [BoxShadow(color: (s.isPremium ? AC.purple : AC.orange).withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(CupertinoIcons.star_fill, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(s.isPremium ? 'Premium activo' : 'Plan Normal', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        for (final k in perks)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(s.isPremium ? CupertinoIcons.checkmark_circle_fill : k.$1, color: Colors.white.withOpacity(0.95), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(k.$2, style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 13.5))),
            ]),
          ),
        if (!s.isPremium) ...[
          const SizedBox(height: 6),
          AppButton(label: 'Pasar a Premium', icon: CupertinoIcons.star_fill, color: Colors.white, outline: true, compact: true, onPressed: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const PaymentScreen()))),
        ],
      ]),
    );
  }
}
