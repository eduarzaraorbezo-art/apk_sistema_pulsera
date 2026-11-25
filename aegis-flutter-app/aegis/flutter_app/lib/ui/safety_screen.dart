import 'dart:math';
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'charts.dart';
import 'home_screen.dart' show mmss;
import 'protection_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});
  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  int _minutes = 30;
  String _label = 'Trayecto';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final c = s.checkin;
    return Page2(
      title: 'Seguridad',
      subtitle: 'Check-in y lugares seguros',
      children: [
        Group(children: [
          Row2(icon: CupertinoIcons.shield_lefthalf_fill, color: AC.purple, title: 'Protección avanzada', subtitle: 'Código de coacción, ubicación en vivo, ruta segura', chevron: true,
              onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const ProtectionScreen()))),
        ]),
        const SectionLabel('Check-in "avísame si no llego"'),
        if (c == null)
          Card2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Programa un tiempo. Si no confirmas que estás bien antes de que termine, AEGIS activa un SOS automáticamente.',
                  style: TextStyle(color: p.secondary)),
              const SizedBox(height: 14),
              Segmented<String>(value: _label, items: const {'Trayecto': 'Trayecto', 'Cita': 'Cita', 'Caminata': 'Caminata'}, onChanged: (v) => setState(() => _label = v)),
              const SizedBox(height: 10),
              Segmented<int>(value: _minutes, items: const {15: '15 min', 30: '30 min', 60: '1 h', 120: '2 h'}, onChanged: (v) => setState(() => _minutes = v)),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: () => s.startCheckin(_label, _minutes), icon: const Icon(CupertinoIcons.timer), label: const Text('Iniciar check-in')),
            ]),
          )
        else
          Card2(
            child: Column(children: [
              Text(c.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.secondary)),
              const SizedBox(height: 10),
              CountdownRing(
                progress: c.totalMs == 0 ? 0 : s.checkinRemainingSec * 1000 / c.totalMs,
                color: s.checkinRemainingSec < 60 ? AC.red : AC.blue,
                child: Text(mmss(s.checkinRemainingSec), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: p.label)),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AC.green),
                  onPressed: s.confirmCheckin, icon: const Icon(CupertinoIcons.check_mark_circled_solid), label: const Text('Estoy bien')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => s.extendCheckin(15), child: const Text('+15 min'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton(onPressed: s.confirmCheckin, child: const Text('Cancelar'))),
              ]),
              const SizedBox(height: 8),
              Text('Funciona mientras AEGIS siga activo en el teléfono (no la cierres desde recientes).', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.secondary)),
            ]),
          ),
        const SizedBox(height: 4),
        SectionLabel('Lugares seguros', trailing: TextButton(onPressed: () => _addPlace(context, s), child: const Text('Agregar aquí'))),
        if (s.places.isEmpty)
          Card2(child: Text('Guarda tu casa, trabajo o universidad. Estando en uno verás "Estás en un lugar seguro".', style: TextStyle(color: p.secondary)))
        else
          FutureBuilder<Position?>(
            future: s.currentPosition(),
            builder: (context, snap) {
              final pos = snap.data;
              return Group(children: [
                for (final pl in s.places)
                  Builder(builder: (_) {
                    final d = pos == null ? null : Geolocator.distanceBetween(pos.latitude, pos.longitude, pl.lat, pl.lon);
                    final inside = d != null && d <= max(pl.radius, 50);
                    return Dismissible(
                      key: ValueKey(pl.id),
                      direction: DismissDirection.endToStart,
                      background: Container(color: AC.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(CupertinoIcons.delete, color: Colors.white)),
                      onDismissed: (_) => s.removePlace(pl.id),
                      child: Container(
                        color: Colors.transparent,
                        child: Row2(
                          icon: CupertinoIcons.house_fill, color: inside ? AC.green : AC.blue, title: pl.name,
                          subtitle: d == null ? 'Radio ${pl.radius} m' : (inside ? 'Estás en un lugar seguro' : 'A ${d >= 1000 ? '${(d / 1000).toStringAsFixed(1)} km' : '${d.round()} m'}'),
                        ),
                      ),
                    );
                  }),
              ]);
            },
          ),
        const SizedBox(height: 4),
        const SectionLabel('Consejos'),
        Group(children: const [
          Row2(icon: CupertinoIcons.battery_25, color: AC.green, title: 'Carga la pulsera cada noche', subtitle: 'Sin batería no hay SOS ni pulsaciones'),
          Row2(icon: CupertinoIcons.person_2_fill, color: AC.blue, title: 'Avisa a tus contactos', subtitle: 'Que sepan que pueden recibir tu alerta'),
          Row2(icon: CupertinoIcons.location_fill, color: AC.orange, title: 'Deja el GPS activado', subtitle: 'Se usa solo durante emergencias y al compartir'),
        ]),
      ],
    );
  }

  Future<void> _addPlace(BuildContext context, AppState s) async {
    final name = TextEditingController();
    var radius = 150.0;
    final ok = await showSheet<bool>(context, (c) => StatefulBuilder(builder: (c, set) {
          final p = Pal.of(c);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Nuevo lugar seguro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(height: 4),
            Text('Se guardará tu ubicación actual.', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(hintText: 'Nombre (Casa, Trabajo…)')),
            const SizedBox(height: 12),
            Text('Radio: ${radius.round()} m', style: TextStyle(color: p.label)),
            Slider.adaptive(value: radius, min: 50, max: 500, divisions: 9, onChanged: (v) => set(() => radius = v)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ]);
        }));
    if (ok != true || name.text.trim().isEmpty) return;
    final err = await s.addPlaceHere(name.text.trim(), radius.round());
    if (err != null && context.mounted) toast(context, err);
  }
}
