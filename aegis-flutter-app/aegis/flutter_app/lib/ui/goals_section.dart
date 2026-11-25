import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'charts.dart';
import 'theme.dart';
import 'widgets.dart';

String _hm(int minutes) => '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';

/// Metas diarias: pasos (contador de la pulsera) y sueño (de la pulsera o registrado a mano).
class GoalsSection extends StatelessWidget {
  const GoalsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final nights = s.sleep.take(7).toList().reversed.toList();
    final last = s.sleep.isEmpty ? null : s.sleep.first;
    final goalMin = (s.sleepGoalH * 60).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel('Metas de hoy', trailing: TextButton(onPressed: () => _editGoals(context, s), child: const Text('Editar'))),
      Card2(
        child: FutureBuilder<int>(
          key: ValueKey(s.latest?.ts),
          future: s.todaySteps(),
          builder: (c, snap) {
            final steps = snap.data ?? 0;
            final pr = (steps / s.stepGoal).clamp(0.0, 1.0);
            return Row(children: [
              CountdownRing(
                progress: pr, color: pr >= 1 ? AC.green : AC.orange, size: 110,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$steps', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
                  Text('pasos', style: TextStyle(fontSize: 11, color: p.secondary)),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pr >= 1 ? '¡Meta cumplida!' : 'Meta: ${s.stepGoal} pasos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.label)),
                  const SizedBox(height: 4),
                  Text(steps == 0 ? 'Conecta la pulsera para contar tus pasos.' : (pr >= 1 ? 'Superaste tu objetivo diario.' : 'Faltan ${s.stepGoal - steps} pasos (~${((s.stepGoal - steps) * 0.00075).toStringAsFixed(1)} km).'),
                      style: TextStyle(color: p.secondary, fontSize: 13)),
                ]),
              ),
            ]);
          },
        ),
      ),
      const SizedBox(height: 10),
      Card2(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(CupertinoIcons.moon_fill, color: AC.purple, size: 20),
            const SizedBox(width: 8),
            Text('Sueño', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.label)),
            const Spacer(),
            TextButton(onPressed: () => _logSleep(context, s), child: const Text('Registrar')),
          ]),
          if (last == null)
            Text('Aún no hay noches registradas. La pulsera las enviará sola; mientras tanto puedes registrarlas a mano.', style: TextStyle(color: p.secondary, fontSize: 13))
          else ...[
            Text(_hm((last['minutes'] as num).toInt()), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: p.label)),
            Text(
              '${(last['minutes'] as num) >= goalMin ? 'Cumpliste tu meta' : 'Te faltaron ${_hm(goalMin - (last['minutes'] as num).toInt())}'} de ${s.sleepGoalH.toStringAsFixed(s.sleepGoalH % 1 == 0 ? 0 : 1)} h${last['quality'] == null ? '' : ' · calidad ${last['quality']} %'}',
              style: TextStyle(color: p.secondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 70,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final n in nights)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          height: 52 * ((n['minutes'] as num) / 600).clamp(0.05, 1.0).toDouble(),
                          decoration: BoxDecoration(color: (n['minutes'] as num) >= goalMin ? AC.purple : AC.purple.withOpacity(0.4), borderRadius: BorderRadius.circular(5)),
                        ),
                        const SizedBox(height: 3),
                        Text((n['night'] as String).substring(8), style: TextStyle(fontSize: 10, color: p.secondary)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }

  Future<void> _logSleep(BuildContext context, AppState s) async {
    final now = DateTime.now();
    var bed = const TimeOfDay(hour: 23, minute: 0), wake = const TimeOfDay(hour: 7, minute: 0);
    String? err;
    final ok = await showSheet<bool>(context, (c) => StatefulBuilder(builder: (c, set) {
          final p = Pal.of(c);
          Future<void> pick(bool isBed) async {
            final t = await showTimePicker(context: c, initialTime: isBed ? bed : wake);
            if (t != null) set(() => isBed ? bed = t : wake = t);
          }

          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Registrar la última noche', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(height: 12),
            Group(children: [
              Row2(icon: CupertinoIcons.moon_fill, color: AC.purple, title: 'Me dormí', value: bed.format(c), chevron: true, onTap: () => pick(true)),
              Row2(icon: CupertinoIcons.sun_max_fill, color: AC.orange, title: 'Desperté', value: wake.format(c), chevron: true, onTap: () => pick(false)),
            ]),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: AC.red))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final end = DateTime(now.year, now.month, now.day, wake.hour, wake.minute);
                var start = DateTime(now.year, now.month, now.day, bed.hour, bed.minute);
                if (!start.isBefore(end)) start = start.subtract(const Duration(days: 1));
                final e = await s.saveSleep(start, end);
                if (e == null) {
                  if (c.mounted) Navigator.pop(c, true);
                } else {
                  set(() => err = 'Revisa las horas: el sueño debe durar entre 20 min y 18 h.');
                }
              },
              child: const Text('Guardar'),
            ),
          ]);
        }));
    if (ok == true && context.mounted) toast(context, 'Noche guardada');
  }

  Future<void> _editGoals(BuildContext context, AppState s) async {
    var steps = s.stepGoal.toDouble(), sleepH = s.sleepGoalH;
    final ok = await showSheet<bool>(context, (c) => StatefulBuilder(builder: (c, set) {
          final p = Pal.of(c);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Tus metas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(height: 12),
            Text('Pasos al día: ${steps.round()}', style: TextStyle(color: p.label)),
            Slider.adaptive(value: steps, min: 2000, max: 20000, divisions: 36, onChanged: (v) => set(() => steps = (v / 500).round() * 500.0)),
            Text('Horas de sueño: ${sleepH.toStringAsFixed(1)}', style: TextStyle(color: p.label)),
            Slider.adaptive(value: sleepH, min: 5, max: 10, divisions: 10, onChanged: (v) => set(() => sleepH = v)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ]);
        }));
    if (ok == true) await s.saveSettings({'step_goal': steps.round(), 'sleep_goal_h': sleepH});
  }
}
