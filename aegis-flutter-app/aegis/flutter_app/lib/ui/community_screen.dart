import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../sync/sync_service.dart';
import '../track/track_state.dart';
import 'map_view.dart';
import 'theme.dart';
import 'widgets.dart';

IconData kindIcon(String k) => switch (k) {
      'safe' => CupertinoIcons.checkmark_shield_fill,
      'unsafe' => CupertinoIcons.exclamationmark_triangle_fill,
      'police' => CupertinoIcons.person_badge_plus_fill,
      'hospital' => CupertinoIcons.plus_app_fill,
      'pharmacy' => CupertinoIcons.capsule_fill,
      'lit' => CupertinoIcons.lightbulb_fill,
      'dark' => CupertinoIcons.moon_fill,
      'crowded' => CupertinoIcons.person_3_fill,
      'shelter' => CupertinoIcons.house_fill,
      _ => CupertinoIcons.map_pin_ellipse,
    };

/// Comunidad: lugares marcados por todos (nunca recorridos de nadie) y alertas SOS cercanas.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  int _tab = 0;
  List<double>? _me;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = context.read<AppState>();
    final pos = await s.trk.position();
    if (pos == null || !mounted) return;
    setState(() => _me = [pos.latitude, pos.longitude]);
    await s.community.refreshPlaces(pos.latitude, pos.longitude);
    await s.community.pollAlerts();
  }

  double _dist(Map<String, dynamic> pl) => _me == null ? 0 : haversineM(_me![0], _me![1], (pl['lat'] as num).toDouble(), (pl['lon'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Comunidad')),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              backgroundColor: AC.blue,
              onPressed: _me == null ? null : () => _addPlace(context, s),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('Marcar lugar aquí'),
            )
          : null,
      body: ListenableBuilder(
        listenable: s.community,
        builder: (context, _) {
          final c = s.community;
          final places = [...c.places]..sort((a, b) => _dist(a).compareTo(_dist(b)));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              Segmented<int>(value: _tab, items: {0: 'Lugares', 1: c.alerts.isEmpty ? 'Alertas' : 'Alertas (${c.alerts.length})'}, onChanged: (v) => setState(() => _tab = v)),
              const SizedBox(height: 12),
              MapView(track: const [], me: _me, places: c.places, alerts: c.alerts, height: 240, onPlaceTap: (pl) => _detail(context, s, pl)),
              const SizedBox(height: 4),
              if (c.offline) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Sin conexión: mostrando los últimos lugares guardados.', style: TextStyle(fontSize: 12, color: p.secondary))),
              if (_me == null) Padding(padding: const EdgeInsets.all(12), child: Text('Esperando tu ubicación… activa el GPS y desliza para actualizar.', style: TextStyle(color: p.secondary))),
              if (_tab == 0) ...[
                const SectionLabel('Cerca de ti'),
                if (places.isEmpty) Card2(child: Text('Aún no hay lugares marcados por aquí. Sé el primero.', style: TextStyle(color: p.secondary))),
                if (places.isNotEmpty)
                  Group(children: [
                    for (final pl in places)
                      Row2(
                        icon: kindIcon(pl['kind'] as String), color: Color((placeKinds[pl['kind']] ?? placeKinds['other']!).$2),
                        title: pl['title'] as String,
                        subtitle: '${(placeKinds[pl['kind']] ?? placeKinds['other']!).$1} · ${_fmtM(_dist(pl))} · ${pl['confirms']} confirman',
                        chevron: true,
                        onTap: () => _detail(context, s, pl),
                      ),
                  ]),
              ] else ...[
                const SectionLabel('Personas que piden ayuda'),
                if (c.alerts.isEmpty) Card2(child: Text('No hay alertas activas cerca. Te avisaremos si alguien a menos de 3 km activa un SOS.', style: TextStyle(color: p.secondary))),
                for (final a in c.alerts) _AlertCard(a: a),
              ],
            ]),
          );
        },
      ),
    );
  }

  String _fmtM(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

  Future<void> _addPlace(BuildContext context, AppState s) async {
    final title = TextEditingController(), note = TextEditingController();
    String kind = 'safe';
    final ok = await showSheet<bool>(context, (c) => StatefulBuilder(builder: (c, set) {
          final p = Pal.of(c);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Marcar este lugar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(height: 4),
            Text('Lo verán todos los usuarios cercanos. No se comparte tu recorrido.', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in placeKinds.entries)
                ChoiceChip(
                  avatar: Icon(kindIcon(e.key), size: 16, color: Color(e.value.$2)),
                  label: Text(e.value.$1), selected: kind == e.key, onSelected: (_) => set(() => kind = e.key),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: title, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Nombre (ej. Parque con serenazgo)')),
            const SizedBox(height: 10),
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(hintText: 'Detalle opcional (ej. mal alumbrado de noche)')),
            const SizedBox(height: 12),
            FilledButton(onPressed: () { if (title.text.trim().length >= 2) Navigator.pop(c, true); }, child: const Text('Publicar')),
          ]);
        }));
    if (ok != true || _me == null) return;
    final r = await Api.addCommunityPlace(kind, title.text.trim(), note.text.trim().isEmpty ? null : note.text.trim(), _me![0], _me![1]);
    if (!mounted) return;
    toast(context, r == null ? 'No se pudo publicar. Revisa tu conexión.' : 'Lugar publicado');
    if (r != null) _refresh();
  }

  void _detail(BuildContext context, AppState s, Map<String, dynamic> pl) {
    final k = placeKinds[pl['kind']] ?? placeKinds['other']!;
    showSheet<void>(context, (c) {
      final p = Pal.of(c);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(kindIcon(pl['kind'] as String), color: Color(k.$2), size: 44),
        const SizedBox(height: 6),
        Text(pl['title'] as String, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
        Text(k.$1, textAlign: TextAlign.center, style: TextStyle(color: Color(k.$2), fontWeight: FontWeight.w700)),
        if ((pl['note'] as String?) != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(pl['note'] as String, textAlign: TextAlign.center, style: TextStyle(color: p.label))),
        const SizedBox(height: 6),
        Text('${pl['confirms']} confirman · ${pl['reports']} reportes', textAlign: TextAlign.center, style: TextStyle(color: p.secondary)),
        const SizedBox(height: 14),
        RoundRow([
          if (pl['mine'] != true) ...[
            RoundBtn(icon: CupertinoIcons.hand_thumbsup_fill, label: 'Confirmo', color: AC.green, onTap: () async { Navigator.pop(c); await Api.voteCommunityPlace(pl['id'] as String, 'confirm'); _refresh(); }),
            RoundBtn(icon: CupertinoIcons.flag_fill, label: 'Reportar', color: AC.orange, onTap: () async { Navigator.pop(c); await Api.voteCommunityPlace(pl['id'] as String, 'report'); _refresh(); }),
          ],
          RoundBtn(icon: CupertinoIcons.location_fill, label: 'Cómo llegar', color: AC.blue, onTap: () => launchUrl(Uri.parse('geo:${pl['lat']},${pl['lon']}?q=${pl['lat']},${pl['lon']}'))),
        ]),
        if (pl['mine'] == true)
          TextButton(onPressed: () async { Navigator.pop(c); await Api.deleteCommunityPlace(pl['id'] as String); _refresh(); }, child: const Text('Eliminar mi lugar', style: TextStyle(color: AC.red))),
      ]);
    });
  }
}

class _AlertCard extends StatefulWidget {
  const _AlertCard({required this.a});
  final Map<String, dynamic> a;
  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _going = false;
  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final p = Pal.of(context);
    return Card2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(CupertinoIcons.exclamationmark_octagon_fill, color: AC.red),
          const SizedBox(width: 8),
          Expanded(child: Text('${a['name']} necesita ayuda', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.label))),
        ]),
        const SizedBox(height: 4),
        Text('A ${a['distance_km']} km · ${a['responders']} personas en camino', style: TextStyle(color: p.secondary)),
        const SizedBox(height: 10),
        Text('Si puedes ayudar sin ponerte en riesgo, ve. Si no, llama al 105 o al 116.', style: TextStyle(fontSize: 12, color: p.secondary)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AC.red),
              onPressed: () async {
                setState(() => _going = true);
                await Api.respondAlert(a['id'] as String);
                await launchUrl(Uri.parse('geo:${a['lat']},${a['lon']}?q=${a['lat']},${a['lon']}'));
              },
              child: Text(_going ? 'Voy en camino ✓' : 'Voy en camino'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => launchUrl(Uri.parse('tel:105')), child: const Text('Llamar 105')),
        ]),
      ]),
    );
  }
}
