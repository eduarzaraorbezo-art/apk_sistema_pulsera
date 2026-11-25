import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../safety/pin_store.dart';
import '../safety/safe_route.dart';
import 'theme.dart';
import 'widgets.dart';

String _left(DateTime? t) {
  if (t == null) return '';
  final m = t.difference(DateTime.now()).inMinutes;
  return m <= 0 ? 'por terminar' : (m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min');
}

/// Protección avanzada: código de coacción, ubicación en vivo y ruta segura.
class ProtectionScreen extends StatefulWidget {
  const ProtectionScreen({super.key});
  @override
  State<ProtectionScreen> createState() => _ProtectionScreenState();
}

class _ProtectionScreenState extends State<ProtectionScreen> {
  bool? _hasPin;
  int _minutes = 120;
  double _corridor = 300;

  @override
  void initState() {
    super.initState();
    _loadPin();
  }

  Future<void> _loadPin() async {
    final h = await PinStore.has();
    if (mounted) setState(() => _hasPin = h);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Protección avanzada')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.liveShare, s.route]),
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          // ---------- coacción ----------
          const SectionLabel('Código de coacción'),
          Card2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dos PIN: uno cancela una alerta de verdad. El otro, que das si alguien te obliga, parece cancelarla pero envía un SOS silencioso con tu ubicación en vivo.',
                  style: TextStyle(color: p.secondary, fontSize: 13)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: FilledButton(onPressed: () => _setPin(context), child: Text(_hasPin == true ? 'Cambiar PIN' : 'Crear PIN'))),
                if (_hasPin == true) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () async { await PinStore.clear(); _loadPin(); }, child: const Text('Quitar', style: TextStyle(color: AC.red))),
                ],
              ]),
            ]),
          ),
          // ---------- en vivo ----------
          const SectionLabel('Me siguen: ubicación en vivo'),
          Card2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!s.liveShare.active) ...[
                Text('Crea un enlace que tus contactos abren sin instalar nada. Caduca solo y puedes cortarlo cuando quieras.', style: TextStyle(color: p.secondary, fontSize: 13)),
                const SizedBox(height: 10),
                Segmented<int>(value: _minutes, items: const {60: '1 h', 120: '2 h', 240: '4 h', 480: '8 h'}, onChanged: (v) => setState(() => _minutes = v)),
                const SizedBox(height: 10),
                FilledButton.icon(
                  icon: const Icon(CupertinoIcons.dot_radiowaves_left_right),
                  label: const Text('Empezar a compartir'),
                  onPressed: () async {
                    final u = await s.liveShare.start(minutes: _minutes);
                    if (context.mounted && u == null) toast(context, 'No se pudo. Revisa el GPS, el permiso y tu conexión.');
                  },
                ),
              ] else ...[
                Row(children: [
                  const Icon(CupertinoIcons.circle_fill, color: AC.green, size: 12),
                  const SizedBox(width: 8),
                  Text('Compartiendo · termina en ${_left(s.liveShare.expires)}', style: TextStyle(fontWeight: FontWeight.w700, color: p.label)),
                ]),
                const SizedBox(height: 8),
                SelectableText(s.liveShare.url ?? '', style: TextStyle(color: AC.blue, fontSize: 13)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(CupertinoIcons.paperplane_fill),
                      label: const Text('Enviar a mis contactos'),
                      onPressed: () async {
                        final o = await s.sendLiveLink();
                        if (context.mounted) toast(context, o);
                      },
                    ),
                  ),
                  IconButton(onPressed: () { Clipboard.setData(ClipboardData(text: s.liveShare.url ?? '')); toast(context, 'Enlace copiado'); }, icon: const Icon(CupertinoIcons.doc_on_doc)),
                ]),
                TextButton(onPressed: s.liveShare.stop, child: const Text('Dejar de compartir', style: TextStyle(color: AC.red))),
              ],
            ]),
          ),
          // ---------- ruta segura ----------
          const SectionLabel('Ruta segura'),
          if (s.route.active || s.route.status == RouteStatus.arrived) _routeStatus(context, s, p) else _routeSetup(context, s, p),
          const SizedBox(height: 12),
          Text('Estas funciones necesitan GPS. El GPS funciona sin internet; el aviso a tus contactos sale cuando haya red o por SMS.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.secondary)),
        ]),
      ),
    );
  }

  Widget _routeStatus(BuildContext context, AppState s, Pal p) {
    final r = s.route;
    final (txt, col) = switch (r.status) {
      RouteStatus.ok => ('En ruta', AC.green),
      RouteStatus.off => ('Fuera de la ruta', AC.orange),
      RouteStatus.arrived => ('Llegaste', AC.blue),
      RouteStatus.idle => ('', AC.gray),
    };
    return Card2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hacia ${r.destName}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.label)),
        const SizedBox(height: 4),
        Text(txt, style: TextStyle(color: col, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Faltan ${r.remainingM.round()} m · a ${r.offsetM.round()} m de la ruta (aviso a más de ${r.corridorM.round()} m)', style: TextStyle(color: p.secondary, fontSize: 13)),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: r.reset, child: Text(r.status == RouteStatus.arrived ? 'Cerrar' : 'Terminar ruta')),
      ]),
    );
  }

  Widget _routeSetup(BuildContext context, AppState s, Pal p) {
    return Card2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Elige a dónde vas. Si te alejas de la ruta más de lo permitido durante 45 s, AEGIS te pregunta si estás bien; si no respondes en 30 s, activa un SOS.', style: TextStyle(color: p.secondary, fontSize: 13)),
        const SizedBox(height: 10),
        Text('Margen permitido: ${_corridor.round()} m', style: TextStyle(color: p.label)),
        Slider.adaptive(value: _corridor, min: 100, max: 1000, divisions: 9, onChanged: (v) => setState(() => _corridor = v)),
        if (s.places.isEmpty) Text('Agrega un lugar seguro en Seguridad para usarlo como destino.', style: TextStyle(color: p.secondary, fontSize: 13)),
        for (final pl in s.places)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(CupertinoIcons.house_fill, color: AC.green),
            title: Text(pl.name),
            subtitle: const Text('Ruta en línea recta'),
            trailing: const Icon(CupertinoIcons.chevron_forward, size: 16),
            onTap: () async {
              final ok = await s.route.startStraight(name: pl.name, lat: pl.lat, lon: pl.lon, corridor: _corridor);
              if (context.mounted && !ok) toast(context, 'No se pudo iniciar. Revisa el GPS y el permiso de ubicación.');
            },
          ),
        FutureBuilder<List<Map<String, Object?>>>(
          future: s.trk.history(),
          builder: (c, snap) {
            final rows = (snap.data ?? []).where((r) => (r['ended'] as int?) != 0 && (r['distance'] as num) > 200).take(5).toList();
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              Text('O repite un recorrido que ya hiciste', style: TextStyle(color: p.secondary, fontSize: 13)),
              for (final r in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.location_fill, color: AC.blue),
                  title: Text('${((r['distance'] as num) / 1000).toStringAsFixed(2)} km'),
                  subtitle: Text(fmtDate(r['started'] as int)),
                  onTap: () async {
                    final pts = s.trk.decodePoints(r['points'] as String);
                    final ok = await s.route.start(name: 'recorrido guardado', polyline: [for (final q in pts) [q[0], q[1]]], corridor: (_corridor < 150 ? 150 : _corridor));
                    if (c.mounted && !ok) toast(c, 'No se pudo iniciar.');
                  },
                ),
            ]);
          },
        ),
      ]),
    );
  }

  Future<void> _setPin(BuildContext context) async {
    final a = TextEditingController(), b = TextEditingController();
    String? err;
    final ok = await showSheet<bool>(context, (c) => StatefulBuilder(builder: (c, set) {
          final p = Pal.of(c);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('PIN y PIN de coacción', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(height: 4),
            Text('De 4 a 6 números cada uno, y distintos. Se guardan solo en este teléfono.', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 12),
            TextField(controller: a, keyboardType: TextInputType.number, obscureText: true, maxLength: 6, decoration: const InputDecoration(hintText: 'Tu PIN normal', counterText: '')),
            const SizedBox(height: 8),
            TextField(controller: b, keyboardType: TextInputType.number, obscureText: true, maxLength: 6, decoration: const InputDecoration(hintText: 'PIN de coacción (SOS silencioso)', counterText: '')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: AC.red))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final e = await PinStore.set(a.text.trim(), b.text.trim());
                if (e == null) {
                  if (c.mounted) Navigator.pop(c, true);
                } else {
                  set(() => err = e == 'same_pin' ? 'Los dos PIN deben ser distintos.' : 'Cada PIN debe tener de 4 a 6 números.');
                }
              },
              child: const Text('Guardar'),
            ),
          ]);
        }));
    if (ok == true) _loadPin();
  }
}
