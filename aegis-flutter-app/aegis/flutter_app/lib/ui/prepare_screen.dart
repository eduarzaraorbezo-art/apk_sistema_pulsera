import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sync/sync_service.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------- avisos del administrador (inicio)
const _lvColor = {'info': AC.blue, 'warning': AC.orange, 'critical': AC.red};

class AnnouncementsBanner extends StatefulWidget {
  const AnnouncementsBanner({super.key});
  @override
  State<AnnouncementsBanner> createState() => _AnnouncementsBannerState();
}

class _AnnouncementsBannerState extends State<AnnouncementsBanner> {
  List<Map<String, dynamic>> _items = const [];
  final _hidden = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    _hidden.addAll(sp.getStringList('ann_hidden') ?? const []);
    final d = await Api.myAnnouncements();
    if (!mounted || d == null) return;
    setState(() => _items = [for (final x in (d['items'] as List)) Map<String, dynamic>.from(x as Map)]);
  }

  Future<void> _dismiss(String id) async {
    setState(() => _hidden.add(id));
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('ann_hidden', _hidden.toList());
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final shown = _items.where((a) => !_hidden.contains(a['id'])).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final a in shown)
        Card2(
          color: (_lvColor[a['level']] ?? AC.blue).withOpacity(0.14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(CupertinoIcons.speaker_2_fill, color: _lvColor[a['level']] ?? AC.blue, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['title']}', style: TextStyle(fontWeight: FontWeight.w800, color: p.label)),
                const SizedBox(height: 2),
                Text('${a['body']}', style: TextStyle(fontSize: 13, color: p.secondary)),
              ]),
            ),
            GestureDetector(onTap: () => _dismiss('${a['id']}'), child: Icon(CupertinoIcons.xmark_circle_fill, size: 20, color: p.secondary)),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- preparación personal
const _kit = <String, List<String>>{
  'Antes de salir': [
    'Teléfono con batería y pulsera cargada',
    'Contactos de confianza actualizados',
    'Compartir mi ruta con alguien',
    'Ficha médica completa',
  ],
  'Kit de emergencia': [
    'Silbato o alarma personal',
    'Linterna pequeña',
    'Dinero en efectivo para transporte',
    'Cargador portátil',
  ],
  'En casa': [
    'Número de emergencias a la vista (105)',
    'Punto de encuentro acordado con la familia',
    'Botiquín básico revisado',
  ],
};

const _tips = [
  ('Camina con confianza', 'Cabeza alta, ritmo constante y evita mirar el teléfono en calles solitarias.'),
  ('Elige rutas iluminadas', 'Usa la ruta segura de AEGIS y evita atajos oscuros.'),
  ('Avisa tu llegada', 'Activa un check-in: si no confirmas, tus contactos reciben la alerta.'),
  ('Confía en tu instinto', 'Si algo no se siente bien, entra a un local abierto y llama a alguien.'),
  ('Prueba tu SOS', 'Practica con tus contactos para que sepan qué hacer cuando lleguen tus alertas.'),
];

class PrepareScreen extends StatefulWidget {
  const PrepareScreen({super.key});
  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends State<PrepareScreen> {
  final _done = <String>{};
  SharedPreferences? _sp;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      _sp = sp;
      if (mounted) setState(() => _done.addAll(sp.getStringList('prep_done') ?? const []));
    });
  }

  void _toggle(String k) {
    setState(() => _done.contains(k) ? _done.remove(k) : _done.add(k));
    _sp?.setStringList('prep_done', _done.toList());
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final total = _kit.values.fold<int>(0, (a, b) => a + b.length);
    final n = _kit.values.expand((e) => e).where(_done.contains).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Preparación')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Card2(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Estás al ${(total == 0 ? 0 : n * 100 / total).round()}%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: total == 0 ? 0 : n / total, minHeight: 10, borderRadius: BorderRadius.circular(8), color: AC.green),
            const SizedBox(height: 6),
            Text('$n de $total puntos listos', style: TextStyle(color: p.secondary, fontSize: 13)),
          ]),
        ),
        for (final e in _kit.entries) ...[
          SectionLabel(e.key),
          Group(children: [
            for (final it in e.value)
              InkWell(
                onTap: () => _toggle(it),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(_done.contains(it) ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle, key: ValueKey(_done.contains(it)), color: _done.contains(it) ? AC.green : p.secondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(it, style: TextStyle(color: p.label, decoration: _done.contains(it) ? TextDecoration.lineThrough : null))),
                  ]),
                ),
              ),
          ]),
        ],
        const SectionLabel('Consejos'),
        for (final t in _tips)
          Card2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.$1, style: TextStyle(fontWeight: FontWeight.w700, color: p.label)),
              const SizedBox(height: 2),
              Text(t.$2, style: TextStyle(fontSize: 13, color: p.secondary)),
            ]),
          ),
      ]),
    );
  }
}
