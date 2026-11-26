import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../safety/pin_store.dart';
import 'theme.dart';
import 'widgets.dart';

// =====================================================================================================
// MODOS DE PROTECCIÓN: un toque cambia cómo se comporta la pulsera según dónde estés
// =====================================================================================================
class _Mode {
  const _Mode(this.id, this.name, this.icon, this.color, this.desc, this.cfg);
  final String id, name, desc;
  final IconData icon;
  final Color color;
  final Map<String, dynamic> cfg;
}

const _modes = [
  _Mode('calle', 'En la calle', CupertinoIcons.location_north_fill, AC.blue, 'SOS rápido (2 s), detección de caídas y grabación automática.',
      {'sos_hold_seconds': 2, 'fall_detection': true, 'auto_sos_message': true, 'auto_record': true}),
  _Mode('casa', 'En casa', CupertinoIcons.house_fill, AC.green, 'SOS normal (3 s), sin detección de caídas para evitar falsas alarmas.',
      {'sos_hold_seconds': 3, 'fall_detection': false, 'auto_sos_message': true, 'auto_record': true}),
  _Mode('noche', 'De noche', CupertinoIcons.moon_fill, AC.purple, 'Máxima protección: SOS en 2 s, caídas y grabación siempre listas.',
      {'sos_hold_seconds': 2, 'fall_detection': true, 'auto_sos_message': true, 'auto_record': true, 'community_alerts': true}),
  _Mode('deporte', 'Deporte', CupertinoIcons.sportscourt_fill, AC.orange, 'SOS mantenido 5 s para no activarlo con el movimiento, sin detección de caídas.',
      {'sos_hold_seconds': 5, 'fall_detection': false, 'auto_sos_message': true}),
];

class ModesScreen extends StatelessWidget {
  const ModesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final cur = s.settings['mode'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('Modos de protección')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Text('Elige cómo quieres que actúe tu pulsera ahora. Se envía a la pulsera al instante.', style: TextStyle(color: p.secondary)),
        const SizedBox(height: 14),
        for (final m in _modes)
          Card2(
            color: cur == m.id ? m.color.withOpacity(0.16) : null,
            onTap: () async {
              final e = await s.saveSettings({...m.cfg, 'mode': m.id});
              if (context.mounted) toast(context, e == null ? 'Modo "${m.name}" activado' : 'Activado en el teléfono; se sincronizará después');
            },
            child: Row(children: [
              IconBadge(m.icon, m.color, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.label)),
                  const SizedBox(height: 2),
                  Text(m.desc, style: TextStyle(fontSize: 13, color: p.secondary)),
                ]),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(cur == m.id ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle, key: ValueKey(cur == m.id), color: cur == m.id ? m.color : p.secondary),
              ),
            ]),
          ),
      ]),
    );
  }
}

// =====================================================================================================
// LOGROS: insignias por usar bien la protección
// =====================================================================================================
class _Badge {
  const _Badge(this.icon, this.color, this.title, this.desc, this.done);
  final IconData icon;
  final Color color;
  final String title, desc;
  final bool done;
}

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  int _steps = 0, _routes = 0, _prep = 0;
  bool _pin = false, _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final steps = await s.todaySteps();
    final routes = (await s.trk.history()).length;
    final pin = await PinStore.has();
    final sp = await SharedPreferences.getInstance();
    final prep = (sp.getStringList('prep_done') ?? const []).length;
    if (!mounted) return;
    setState(() { _steps = steps; _routes = routes; _pin = pin; _prep = prep; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final badges = [
      _Badge(CupertinoIcons.person_2_fill, AC.blue, 'Red de confianza', 'Ten 3 o más contactos de emergencia', s.contacts.length >= 3),
      _Badge(CupertinoIcons.bluetooth, AC.purple, 'Pulsera vinculada', 'Conecta tu pulsera', s.bandConnected),
      _Badge(CupertinoIcons.flame_fill, AC.orange, 'Meta de pasos', 'Llega a tu meta diaria de pasos', s.stepGoal > 0 && _steps >= s.stepGoal),
      _Badge(CupertinoIcons.location_north_fill, AC.green, 'Primer recorrido', 'Guarda un recorrido con GPS', _routes >= 1),
      _Badge(CupertinoIcons.lock_fill, AC.red, 'PIN de coacción', 'Configura tu PIN de coacción', _pin),
      _Badge(CupertinoIcons.checkmark_shield_fill, AC.teal, 'Bien preparado', 'Completa 8 puntos de Preparación', _prep >= 8),
      _Badge(CupertinoIcons.hand_raised_fill, AC.pink, 'Maestro de gestos', 'Asigna acción a los 5 gestos', ['sos_double', 'sos_triple', 'aux_short', 'aux_double', 'aux_hold'].every((g) => s.gestureCfg(g)['action'] != 'none')),
      _Badge(CupertinoIcons.moon_fill, AC.purple, 'Modo elegido', 'Activa un modo de protección', s.settings['mode'] != null),
    ];
    final n = badges.where((b) => b.done).length;
    final level = n >= 7 ? 'Guardián' : (n >= 4 ? 'Protegido' : (n >= 2 ? 'Aprendiz' : 'Novato'));
    return Scaffold(
      appBar: AppBar(title: const Text('Logros')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              Card2(
                child: Row(children: [
                  SizedBox(
                    width: 70, height: 70,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(child: CircularProgressIndicator(value: n / badges.length, strokeWidth: 8, backgroundColor: AC.green.withOpacity(0.2), color: AC.green)),
                      Text('$n/${badges.length}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: p.label)),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Nivel: $level', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
                      Text('Cada logro mejora tu protección real.', style: TextStyle(color: p.secondary, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.95,
                children: [
                  for (final b in badges)
                    Opacity(
                      opacity: b.done ? 1 : 0.55,
                      child: Card2(
                        margin: EdgeInsets.zero,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          IconBadge(b.done ? b.icon : CupertinoIcons.lock_fill, b.done ? b.color : AC.gray, size: 56),
                          const SizedBox(height: 10),
                          Text(b.title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: p.label)),
                          const SizedBox(height: 2),
                          Text(b.desc, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 11.5, color: p.secondary)),
                        ]),
                      ),
                    ),
                ],
              ),
            ]),
    );
  }
}
