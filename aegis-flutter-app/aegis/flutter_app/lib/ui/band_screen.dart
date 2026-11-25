import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

const actionLabels = {
  'none': 'Ninguna',
  'sos': 'Activar SOS',
  'message': 'Enviar mensaje',
  'share_location': 'Compartir ubicación',
  'checkin_ok': 'Confirmar check-in',
  'find_phone': 'Hacer sonar el teléfono',
  'fake_call': 'Llamada falsa',
  'record': 'Grabar evidencia (Premium)',
  'silent_sos': 'SOS silencioso',
  'live_share': 'Compartir ubicación en vivo',
};
const _actionIcons = {
  'none': CupertinoIcons.minus_circle,
  'sos': CupertinoIcons.exclamationmark_shield_fill,
  'message': CupertinoIcons.paperplane_fill,
  'share_location': CupertinoIcons.location_fill,
  'checkin_ok': CupertinoIcons.check_mark_circled_solid,
  'find_phone': CupertinoIcons.bell_fill,
  'fake_call': CupertinoIcons.phone_fill_arrow_down_left,
  'record': CupertinoIcons.mic_fill,
  'silent_sos': CupertinoIcons.bell_slash_fill,
  'live_share': CupertinoIcons.dot_radiowaves_left_right,
};
const _gestures = [
  ('sos_double', 'Botón SOS · 2 pulsaciones'),
  ('sos_triple', 'Botón SOS · 3 pulsaciones'),
  ('aux_short', 'Botón AUX · pulsación corta'),
  ('aux_double', 'Botón AUX · doble pulsación'),
  ('aux_hold', 'Botón AUX · mantener'),
];

/// Configuración de la pulsera: qué hace cada botón, mensajes, caídas y módulo de defensa.
class BandScreen extends StatelessWidget {
  const BandScreen({super.key});

  String _valueFor(AppState s, Map<String, dynamic> cfg) {
    final a = cfg['action'] as String? ?? 'none';
    if (a == 'message') {
      final t = s.templates.where((x) => x['id'] == cfg['message_id']).toList();
      return t.isEmpty ? 'Mensaje' : '"${t.first['text']}"';
    }
    return actionLabels[a] ?? a;
  }

  Future<void> _pick(BuildContext context, AppState s, String gesture, String title) async {
    await showSheet<void>(context, (c) {
      final p = Pal.of(c);
      Future<void> set(Map<String, dynamic> cfg) async {
        final g = Map<String, dynamic>.from(s.settings['gestures'] as Map);
        g[gesture] = cfg;
        Navigator.pop(c);
        final e = await s.saveSettings({'gestures': g});
        if (context.mounted && e != null) toast(context, 'Guardado en el teléfono; no se pudo respaldar (${errText(e)})');
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.label)),
        const SizedBox(height: 12),
        Group(children: [
          for (final a in actionLabels.keys.where((k) => k != 'message'))
            Row2(icon: _actionIcons[a]!, color: a == 'sos' ? AC.red : AC.blue, title: actionLabels[a]!, onTap: () => set({'action': a})),
        ]),
        const SectionLabel('Enviar un mensaje rápido'),
        Group(children: [
          for (final t in s.templates)
            Row2(icon: CupertinoIcons.paperplane_fill, color: AC.green, title: '${t['text']}', onTap: () => set({'action': 'message', 'message_id': t['id']})),
        ]),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final bat = s.latest?.battery;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi pulsera'), backgroundColor: p.bg, surfaceTintColor: Colors.transparent),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Card2(
          child: Row(children: [
            IconBadge(CupertinoIcons.bluetooth, s.bandConnected ? AC.blue : AC.gray, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.bandConnected ? 'Conectada' : 'Desconectada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.label)),
                Text(bat == null ? 'AEGIS Smart Safety Band' : 'Batería $bat %', style: TextStyle(color: p.secondary)),
              ]),
            ),
            if (!s.bandConnected) FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 38)), onPressed: s.rescanBand, child: const Text('Buscar')),
          ]),
        ),
        Group(children: [
          Row2(icon: CupertinoIcons.bell_circle_fill, color: AC.orange, title: 'Hacer sonar la pulsera', subtitle: 'Si no la encuentras', chevron: true, onTap: s.ringBand),
        ]),
        const SectionLabel('Botones'),
        Group(children: [
          Row2(
            icon: CupertinoIcons.exclamationmark_shield_fill, color: AC.red,
            title: 'Botón SOS · mantener ${s.settings['sos_hold_seconds']} s', value: 'SOS', subtitle: 'Siempre activa el SOS, aunque no haya teléfono cerca',
          ),
          for (final g in _gestures)
            Builder(builder: (_) {
              final cfg = s.gestureCfg(g.$1);
              final a = cfg['action'] as String? ?? 'none';
              return Row2(
                icon: _actionIcons[a] ?? CupertinoIcons.circle, color: a == 'sos' ? AC.red : AC.blue,
                title: g.$2, value: _valueFor(s, cfg), chevron: true,
                onTap: () => _pick(context, s, g.$1, g.$2),
              );
            }),
        ]),
        Card2(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tiempo para activar el SOS: ${s.settings['sos_hold_seconds']} s', style: TextStyle(color: p.label, fontWeight: FontWeight.w600)),
            Slider.adaptive(
              value: ((s.settings['sos_hold_seconds'] as int?) ?? 3).toDouble(), min: 2, max: 5, divisions: 3,
              onChanged: (v) => s.saveSettings({'sos_hold_seconds': v.round()}),
            ),
            Text('Menos tiempo = más rápido, pero más riesgo de activarlo sin querer.', style: TextStyle(fontSize: 12, color: p.secondary)),
          ]),
        ),
        const SectionLabel('Probar una acción'),
        Group(children: [
          for (final g in _gestures)
            Row2(
              icon: CupertinoIcons.play_circle_fill, color: AC.green, title: g.$2,
              subtitle: 'Ejecuta lo asignado, sin usar la pulsera', chevron: true,
              onTap: () {
                final cfg = s.gestureCfg(g.$1);
                s.runAction(cfg['action'] as String? ?? 'none', messageId: cfg['message_id'] as String?);
              },
            ),
        ]),
        const SectionLabel('Protección'),
        Group(children: [
          Row2(
            icon: CupertinoIcons.person_2_fill, color: AC.blue, title: 'Avisar a mis contactos al activar SOS',
            subtitle: 'El servidor les envía tu ubicación',
            trailing: Switch.adaptive(value: s.settings['auto_sos_message'] == true, onChanged: (v) => s.saveSettings({'auto_sos_message': v})),
          ),
          Row2(
            icon: CupertinoIcons.arrow_down_circle_fill, color: AC.orange, title: 'Detección de caídas',
            subtitle: 'Cuenta atrás de 30 s y SOS si no respondes',
            trailing: Switch.adaptive(value: s.settings['fall_detection'] == true, onChanged: (v) => s.saveSettings({'fall_detection': v})),
          ),
          if (s.demo || !s.bandConnected)
            Row2(icon: CupertinoIcons.exclamationmark_triangle_fill, color: AC.pink, title: 'Simular una caída', subtitle: 'Para probar la pantalla de confirmación', chevron: true, onTap: s.simulateFall),
          Row2(
            icon: CupertinoIcons.shield_lefthalf_fill, color: AC.gray, title: 'Módulo de defensa', value: 'Reservado', chevron: true,
            onTap: () => showSheet<void>(context, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(CupertinoIcons.lock_shield_fill, size: 48, color: AC.gray),
                  Text('Módulo de defensa', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Pal.of(c).label)),
                  const SizedBox(height: 8),
                  Text(
                      'La pulsera tendrá un módulo de defensa (agente irritante) con doble seguro: se arma con una acción deliberada, solo se dispara con una acción física en la pulsera y, al usarse, pide ayuda automáticamente.\n\n'
                      'Aún no existe el hardware y hay que revisar la normativa antes de fabricarlo, por eso está desactivado. El protocolo y el servidor ya lo contemplan, así que activarlo en el futuro no obligará a rehacer la app.',
                      style: TextStyle(color: Pal.of(c).secondary)),
                ])),
          ),
        ]),
      ]),
    );
  }
}
