import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../sync/sync_service.dart';
import 'theme.dart';
import 'widgets.dart';

const _alertNames = {1: 'Caída detectada', 2: 'Batería baja', 3: 'Pulsera fuera de la muñeca', 4: 'Manipulación', 5: 'Defensa armada', 6: 'Defensa activada', 7: 'Defensa desarmada'};

/// Historial de gestos y alertas de la pulsera, tal como los guardó el servidor.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<Map<String, dynamic>>? _ev;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.events();
    if (!mounted) return;
    setState(() { _ev = r; _err = r == null; });
  }

  (IconData, Color, String) _describe(Map<String, dynamic> e) {
    switch (e['kind']) {
      case 'gesture':
        return (CupertinoIcons.hand_point_right_fill, AC.blue, 'Gesto → ${e['action'] ?? ''}');
      case 'band_alert':
        final c = e['code'] is int ? e['code'] as int : 0;
        return (CupertinoIcons.exclamationmark_triangle_fill, c == 1 || c == 6 ? AC.red : AC.orange, _alertNames[c] ?? 'Alerta de la pulsera');
      default:
        return (CupertinoIcons.circle_fill, AC.gray, '${e['kind'] ?? 'Evento'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Actividad')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_ev == null && !_err) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator.adaptive())),
          if (_err) Card2(child: Text('No se pudo cargar. Revisa tu conexión y desliza para reintentar.', style: TextStyle(color: p.secondary))),
          if (_ev != null && _ev!.isEmpty) Card2(child: Text('Aún no hay actividad sincronizada.', style: TextStyle(color: p.secondary))),
          if (_ev != null && _ev!.isNotEmpty)
            Group(children: [
              for (final e in _ev!)
                Builder(builder: (_) {
                  final d = _describe(e);
                  final t = DateTime.tryParse('${e['ts']}')?.toLocal();
                  return Row2(icon: d.$1, color: d.$2, title: d.$3, subtitle: t == null ? null : fmtDate(t.millisecondsSinceEpoch));
                }),
            ]),
        ]),
      ),
    );
  }
}
