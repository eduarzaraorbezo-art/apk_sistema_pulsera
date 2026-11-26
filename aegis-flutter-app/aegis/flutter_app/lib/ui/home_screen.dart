import 'dart:ui' show FontFeature;
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../health/reading.dart';
import 'band_screen.dart';
import 'charts.dart';
import 'community_screen.dart';
import 'evidence_screen.dart';
import 'insights_screen.dart';
import 'prepare_screen.dart';
import 'routes_screen.dart';
import 'messages_screen.dart';
import 'pin_pad.dart';
import 'profile_screen.dart' show MedicalIdSheet;
import 'theme.dart';
import 'widgets.dart';

String mmss(int sec) => '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

/// Activa el SOS (guarda local primero) y muestra qué hacer a continuación.
Future<void> triggerSos(BuildContext context) async {
  final s = context.read<AppState>();
  HapticFeedback.heavyImpact();
  final id = await s.sosFromScreen();
  if (!context.mounted) return;
  await showSheet(context, (c) {
    final p = Pal.of(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(CupertinoIcons.exclamationmark_shield_fill, color: AC.red, size: 56),
      const SizedBox(height: 8),
      Text('SOS activado', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.label)),
      const SizedBox(height: 6),
      Text('Quedó guardado en tu teléfono y se enviará en cuanto haya conexión. Esta app no avisa por sí sola a ninguna autoridad: llama tú.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: p.secondary)),
      const SizedBox(height: 16),
      RoundRow([
        RoundBtn(icon: CupertinoIcons.phone_fill, label: 'Llamar 105', color: AC.red, size: 76, onTap: () => launchUrl(Uri.parse('tel:105'))),
        RoundBtn(
          icon: CupertinoIcons.chat_bubble_fill, label: 'Avisar contactos', color: AC.blue, size: 76,
          onTap: () async {
            if (!await s.alertContacts(sosActive: true) && c.mounted) toast(c, 'Agrega contactos primero');
          },
        ),
      ]),
      const SizedBox(height: 6),
      TextButton(
        onPressed: id == null
            ? () => Navigator.pop(c)
            : () async {
                final r = await askPin(c, title: 'PIN para cancelar');
                if (r == null || !await s.afterPin(r)) return;
                await s.markFalseAlarm(id);
                if (c.mounted) Navigator.pop(c);
              },
        child: const Text('Fue una falsa alarma', style: TextStyle(fontSize: 16)),
      ),
    ]);
  });
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final l = s.latest;
    return Page2(
      title: s.displayName.isEmpty ? 'AEGIS' : 'Hola, ${s.displayName}',
      subtitle: s.bandConnected ? 'Protección activa' : (s.demo ? 'Modo demostración' : 'Pulsera sin conectar'),
      children: [
        _StatusStrip(s),
        const AnnouncementsBanner(),
        if (s.alert != null) _AlertBanner(s),
        if (s.checkin != null)
          Card2(
            onTap: () => s.setTab(2),
            color: AC.blue.withOpacity(0.14),
            child: Row(children: [
              const Icon(CupertinoIcons.timer, color: AC.blue),
              const SizedBox(width: 10),
              Expanded(child: Text('Check-in "${s.checkin!.label}" · confirma antes de que acabe', style: TextStyle(color: p.label, fontWeight: FontWeight.w600))),
              Text(mmss(s.checkinRemainingSec), style: const TextStyle(color: AC.blue, fontWeight: FontWeight.w800, fontSize: 18, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          ),
        _BandCard(s),
        const SizedBox(height: 4),
        Center(child: SosHoldButton(onTriggered: () => triggerSos(context))),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          QuickAction(icon: CupertinoIcons.timer, color: AC.blue, label: 'Check-in', onTap: () => s.setTab(2)),
          QuickAction(
              icon: CupertinoIcons.location_fill, color: AC.green, label: 'Compartir ubicación',
              onTap: () async { if (!await s.alertContacts() && context.mounted) toast(context, 'Agrega contactos primero'); }),
          QuickAction(icon: CupertinoIcons.phone_fill, color: AC.red, label: 'Llamar 105', onTap: () => launchUrl(Uri.parse('tel:105'))),
          QuickAction(icon: CupertinoIcons.heart_fill, color: AC.orange, label: 'Ficha médica', onTap: () => showSheet(context, (_) => MedicalIdSheet(profile: s.profile))),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          QuickAction(icon: CupertinoIcons.paperplane_fill, color: AC.teal, label: 'Mensajes', onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const MessagesScreen()))),
          QuickAction(icon: CupertinoIcons.bluetooth, color: AC.purple, label: 'Pulsera', onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const BandScreen()))),
          QuickAction(icon: CupertinoIcons.phone_arrow_down_left, color: AC.gray, label: 'Llamada falsa', onTap: () => s.startFakeCall()),
          QuickAction(icon: CupertinoIcons.bell_fill, color: AC.pink, label: 'Buscar teléfono', onTap: () => s.startFindPhone()),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          QuickAction(icon: CupertinoIcons.location_north_fill, color: AC.blue, label: 'Mi recorrido', onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const RoutesScreen()))),
          QuickAction(icon: CupertinoIcons.map_fill, color: AC.green, label: 'Comunidad', onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const CommunityScreen()))),
          QuickAction(icon: CupertinoIcons.mic_fill, color: AC.red, label: 'Evidencias', onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const EvidenceScreen()))),
          QuickAction(icon: CupertinoIcons.chart_bar_alt_fill, color: AC.orange, label: 'Resumen', onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const InsightsScreen()))),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          QuickAction(icon: CupertinoIcons.checkmark_shield_fill, color: AC.green, label: 'Preparación', onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const PrepareScreen()))),
          const Spacer(), const Spacer(), const Spacer(),
        ]),
        const SizedBox(height: 16),
        const PlanCard(),
        _HeartCard(s),
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.15,
          children: [
            StatTile(icon: CupertinoIcons.drop_fill, color: AC.teal, label: 'SpO₂', value: l?.spo2?.toString() ?? '--', unit: '%'),
            StatTile(icon: CupertinoIcons.thermometer, color: AC.orange, label: 'Temp.', value: l?.tempC?.toStringAsFixed(1) ?? '--', unit: '°C'),
            StatTile(icon: CupertinoIcons.person_2_fill, color: AC.green, label: 'Pasos', value: l?.steps?.toString() ?? '--'),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('Números de emergencia (Perú)'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in {'Policía': '105', 'Bomberos': '116', 'SAMU': '106', 'Línea 100': '100'}.entries)
            ActionChip(
              avatar: const Icon(CupertinoIcons.phone, size: 16),
              label: Text('${e.key} ${e.value}'),
              onPressed: () => launchUrl(Uri.parse('tel:${e.value}')),
              shape: const StadiumBorder(),
              side: BorderSide.none,
              backgroundColor: p.glass,
            ),
        ]),
        const SizedBox(height: 12),
        SectionLabel('Emergencias recientes'),
        if (s.emergencies.isEmpty)
          Card2(child: Text('Sin emergencias registradas.', style: TextStyle(color: p.secondary)))
        else
          Group(children: [
            for (final e in s.emergencies.take(4))
              Row2(
                icon: e['status'] == 'CANCELLED' ? CupertinoIcons.xmark : CupertinoIcons.exclamationmark_triangle_fill,
                color: e['status'] == 'CANCELLED' ? AC.gray : AC.red,
                title: fmtDate(e['started_at'] as int),
                subtitle: '${_src(e['source'] as String?)} · ${e['lat'] != null ? 'con ubicación' : 'sin ubicación'}',
                value: e['status'] == 'CANCELLED' ? 'Falsa alarma' : null,
              ),
          ]),
      ],
    );
  }

  static String _src(String? s) => switch (s) { 'band' => 'Pulsera', 'screen' => 'Pantalla', 'checkin' => 'Check-in vencido', _ => s ?? '' };
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), children: [
            Pill(s.bandConnected ? 'Pulsera conectada' : (s.demo ? 'Demostración' : 'Pulsera desconectada'), icon: CupertinoIcons.bluetooth, color: s.bandConnected ? AC.green : AC.gray),
            const SizedBox(width: 8),
            Pill(s.trk.active ? 'GPS activo' : 'GPS en espera', icon: CupertinoIcons.location_fill, color: s.trk.active ? AC.blue : AC.gray),
            const SizedBox(width: 8),
            if (s.rec.active && !s.rec.silent) ...[const Pill('Grabando', icon: CupertinoIcons.circle_fill, color: AC.red), const SizedBox(width: 8)],
            Pill(s.pending == 0 ? 'Sincronizado' : '${s.pending} por enviar', icon: CupertinoIcons.cloud_fill, color: s.pending == 0 ? AC.teal : AC.orange),
            const SizedBox(width: 8),
            Pill(s.isPremium ? 'Premium' : 'Normal', icon: CupertinoIcons.star_fill, color: s.isPremium ? AC.purple : AC.gray, filled: s.isPremium),
          ]),
        ),
      );
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    final high = s.alert == HrLevel.high;
    return Card2(
      color: AC.red.withOpacity(0.14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(CupertinoIcons.heart_fill, color: AC.red),
          const SizedBox(width: 8),
          Expanded(child: Text('Frecuencia cardíaca ${high ? 'alta' : 'baja'}: ${s.latest?.hr ?? '--'} lpm', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AC.red))),
        ]),
        const SizedBox(height: 6),
        Text('Estuvo fuera de tu rango (${s.hrMin}–${s.hrMax}) varias lecturas seguidas. ¿Estás bien?', style: TextStyle(color: Pal.of(context).label)),
        const SizedBox(height: 10),
        RoundRow([
          RoundBtn(icon: CupertinoIcons.check_mark, label: 'Estoy bien', color: AC.green, onTap: s.dismissAlert),
          RoundBtn(icon: CupertinoIcons.exclamationmark_triangle_fill, label: 'Pedir ayuda', color: AC.red, onTap: () { s.dismissAlert(); triggerSos(context); }),
        ]),
      ]),
    );
  }
}

class _BandCard extends StatelessWidget {
  const _BandCard(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final bat = s.latest?.battery;
    final sync = switch (s.syncLabel) {
      'ONLINE' => ('En línea', AC.green),
      'SYNCING' => ('Sincronizando', AC.blue),
      'PENDING' => ('Pendiente (${s.pending})', AC.orange),
      _ => ('Sin conexión', AC.gray),
    };
    return Card2(
      child: Row(children: [
        IconBadge(CupertinoIcons.bluetooth, s.bandConnected ? AC.blue : AC.gray, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.bandConnected ? 'Pulsera conectada' : 'Pulsera desconectada', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.label)),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: sync.$2, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(sync.$1, style: TextStyle(fontSize: 13, color: p.secondary)),
              if (s.lastSync != 0) Text(' · última ${fmtDate(s.lastSync)}', style: TextStyle(fontSize: 13, color: p.secondary)),
            ]),
          ]),
        ),
        if (bat != null && (s.bandConnected || s.demo))
          Row(children: [
            Icon(bat > 20 ? Icons.battery_full : Icons.battery_alert, size: 20, color: bat > 20 ? AC.green : AC.red),
            Text(' $bat%', style: TextStyle(color: p.secondary, fontWeight: FontWeight.w600)),
          ])
        else if (!s.bandConnected)
          TextButton(onPressed: s.rescanBand, child: const Text('Buscar')),
      ]),
    );
  }
}

class _HeartCard extends StatelessWidget {
  const _HeartCard(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final hr = s.latest?.hr;
    final lvl = s.hrState;
    final chip = switch (lvl) {
      HrLevel.normal => ('Normal', AC.green),
      HrLevel.high => ('Alta', AC.red),
      HrLevel.low => ('Baja', AC.orange),
      HrLevel.none => ('Sin datos', AC.gray),
    };
    final series = [for (final r in s.live.reversed.take(60).toList().reversed) if (r.hr != null) r.hr!];
    return Card2(
      onTap: () => s.setTab(1),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PulsingHeart(bpm: hr, size: 22),
          const SizedBox(width: 8),
          const Text('Frecuencia cardíaca', style: TextStyle(color: AC.red, fontWeight: FontWeight.w700, fontSize: 15)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: chip.$2.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(chip.$1, style: TextStyle(color: chip.$2, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        if (hr == null) ...[
          Text('Conecta tu pulsera para ver tus pulsaciones en vivo.', style: TextStyle(color: p.secondary)),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => s.setDemo(true), child: const Text('Probar con modo demostración'))),
        ] else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$hr', style: TextStyle(fontSize: 52, fontWeight: FontWeight.w800, color: p.label, height: 1)),
            const SizedBox(width: 6),
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('lpm', style: TextStyle(fontSize: 16, color: p.secondary))),
          ]),
          const SizedBox(height: 8),
          Sparkline(series),
        ],
      ]),
    );
  }
}
