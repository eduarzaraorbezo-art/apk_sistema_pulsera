import 'dart:convert';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import 'map_view.dart';
import 'theme.dart';
import 'widgets.dart';

String _km(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.round()} m';
String _dur(int s) => s >= 3600 ? '${s ~/ 3600} h ${(s % 3600) ~/ 60} min' : '${s ~/ 60} min ${s % 60} s';

/// Mi recorrido: registra por GPS (sin internet), muestra distancia, pasos y ritmo. Los recorridos son PRIVADOS.
class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mi recorrido')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.trk, s.community]),
        builder: (context, _) {
          final t = s.trk;
          final me = t.last == null ? null : [t.last!.latitude, t.last!.longitude];
          return ListView(padding: const EdgeInsets.all(16), children: [
            MapView(track: t.points, me: me, places: s.community.places, height: 300),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: StatTile(icon: CupertinoIcons.arrow_right_arrow_left, label: 'Distancia', value: _km(t.distance), color: AC.blue)),
              const SizedBox(width: 10),
              Expanded(child: StatTile(icon: CupertinoIcons.person_fill, label: 'Pasos (aprox.)', value: '${t.steps}', color: AC.green)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: StatTile(icon: CupertinoIcons.timer, label: 'Tiempo', value: t.active ? _dur(t.elapsedSec) : '—', color: AC.orange)),
              const SizedBox(width: 10),
              Expanded(child: StatTile(icon: CupertinoIcons.speedometer, label: 'Ritmo', value: t.paceMinPerKm == 0 ? '—' : '${t.paceMinPerKm.toStringAsFixed(1)} min/km', color: AC.purple)),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: t.active ? AC.red : AC.green, minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              icon: Icon(t.active ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill),
              label: Text(t.active ? 'Terminar recorrido' : 'Empezar recorrido', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              onPressed: () async {
                if (t.active) {
                  await t.stop();
                  s.syncNow();
                } else {
                  final ok = await t.start();
                  if (!ok && context.mounted && t.error != null) toast(context, t.error!);
                }
              },
            ),
            if (t.error != null && !t.active) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.error!, style: const TextStyle(color: AC.red))),
            const SizedBox(height: 8),
            Text('Funciona sin internet: el GPS guarda tu ruta en el teléfono y la sube cuando haya red. Solo tú ves tus recorridos.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.secondary)),
            const SectionLabel('Historial'),
            FutureBuilder<List<Map<String, Object?>>>(
              future: t.history(),
              builder: (c, snap) {
                final rows = (snap.data ?? []).where((r) => r['id'] != t.id || !t.active).toList();
                if (rows.isEmpty) return Card2(child: Text('Aún no tienes recorridos.', style: TextStyle(color: p.secondary)));
                return Group(children: [
                  for (final r in rows)
                    Row2(
                      icon: CupertinoIcons.location_fill, color: AC.blue,
                      title: _km((r['distance'] as num).toDouble()),
                      subtitle: '${fmtDate(r['started'] as int)} · ${r['ended'] == 0 ? 'sin cerrar' : _dur((((r['ended'] as int) - (r['started'] as int)) / 1000).round())} · ${r['steps']} pasos',
                      chevron: true,
                      onTap: () => _open(context, s, r),
                    ),
                ]);
              },
            ),
          ]);
        },
      ),
    );
  }

  void _open(BuildContext context, AppState s, Map<String, Object?> r) {
    final pts = [for (final e in jsonDecode(r['points'] as String) as List) [for (final n in e as List) (n as num).toDouble()]];
    showSheet<void>(context, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_km((r['distance'] as num).toDouble()), textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Pal.of(c).label)),
          Text(fmtDate(r['started'] as int), textAlign: TextAlign.center, style: TextStyle(color: Pal.of(c).secondary)),
          const SizedBox(height: 12),
          MapView(track: pts, height: 260),
          const SizedBox(height: 12),
          if (pts.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.map),
              label: const Text('Ver inicio en Mapas'),
              onPressed: () => launchUrl(Uri.parse('geo:${pts.first[0]},${pts.first[1]}?q=${pts.first[0]},${pts.first[1]}')),
            ),
          TextButton(
            onPressed: () async { Navigator.pop(c); await s.trk.remove(r['id'] as String); },
            child: const Text('Eliminar recorrido', style: TextStyle(color: AC.red)),
          ),
        ]));
  }
}
