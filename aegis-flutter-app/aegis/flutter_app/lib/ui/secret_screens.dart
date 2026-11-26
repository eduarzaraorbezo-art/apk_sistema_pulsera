import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

// =====================================================================================================
// PROBAR GESTOS: simula cada gesto de la pulsera sin mandar nada de verdad
// =====================================================================================================
class GestureTestScreen extends StatelessWidget {
  const GestureTestScreen({super.key});

  static const _gestures = [
    ('sos_double', 'SOS · 2 toques', CupertinoIcons.hand_raised_fill, AC.red),
    ('sos_triple', 'SOS · 3 toques', CupertinoIcons.exclamationmark_triangle_fill, AC.red),
    ('aux_short', 'Aux · 1 toque', CupertinoIcons.circle_fill, AC.blue),
    ('aux_double', 'Aux · 2 toques', CupertinoIcons.plus_circle_fill, AC.blue),
    ('aux_hold', 'Aux · mantener', CupertinoIcons.timer, AC.purple),
  ];

  String _describe(AppState s, Map<String, dynamic> cfg) {
    switch (cfg['action'] as String? ?? 'none') {
      case 'message':
        final t = s.templates.where((x) => x['id'] == cfg['message_id']).toList();
        return t.isEmpty ? 'Enviaría un mensaje a tus contactos' : 'Enviaría a tus contactos: "${t.first['text']}"';
      case 'share_location':
        return 'Compartiría tu ubicación con tus contactos';
      case 'checkin_ok':
        return s.checkin != null ? 'Confirmaría tu check-in activo' : 'Confirmaría tu check-in (ahora no hay uno activo)';
      case 'find_phone':
        return 'Haría sonar tu teléfono';
      case 'fake_call':
        return 'Simularía una llamada entrante';
      case 'sos':
      case 'silent_sos':
        return 'Activaría un SOS';
      default:
        return 'No tiene ninguna acción asignada';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Probar gestos')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Text('Toca un círculo para ver qué haría ese gesto. Es una simulación: no se envía nada.', style: TextStyle(color: p.secondary)),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          runSpacing: 18,
          children: [
            for (final g in _gestures)
              RoundBtn(
                icon: g.$3, label: g.$2, color: g.$4, size: 78,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  final cfg = s.gestureCfg(g.$1);
                  showSheet(context, (c) => Column(mainAxisSize: MainAxisSize.min, children: [
                        IconBadge(g.$3, g.$4, size: 56),
                        const SizedBox(height: 12),
                        Text(g.$2, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Pal.of(c).label)),
                        const SizedBox(height: 6),
                        Text(_describe(s, cfg), textAlign: TextAlign.center, style: TextStyle(color: Pal.of(c).secondary, fontSize: 15)),
                        const SizedBox(height: 18),
                      ]));
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Para cambiar lo que hace cada gesto, ve a Pulsera.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.secondary)),
      ]),
    );
  }
}

// =====================================================================================================
// PALABRA CLAVE: una palabra secreta que solo conocen tú y tus contactos
// =====================================================================================================
class CodewordScreen extends StatefulWidget {
  const CodewordScreen({super.key});
  @override
  State<CodewordScreen> createState() => _CodewordScreenState();
}

class _CodewordScreenState extends State<CodewordScreen> {
  final _c = TextEditingController();
  String? _word;
  bool _show = false;
  SharedPreferences? _sp;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      _sp = sp;
      if (mounted) setState(() => _word = sp.getString('codeword'));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Palabra clave')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Card2(
          child: Column(children: [
            const IconBadge(CupertinoIcons.lock_shield_fill, AC.purple, size: 60),
            const SizedBox(height: 10),
            Text('Una palabra que solo conocen los tuyos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.label), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('Si alguien dice venir de tu parte, o te llama diciendo que estás en peligro, pídele la palabra. Si no la sabe, no es de confianza.',
                textAlign: TextAlign.center, style: TextStyle(color: p.secondary, fontSize: 13)),
          ]),
        ),
        if (_word != null) ...[
          const SectionLabel('Tu palabra'),
          Card2(
            onTap: () => setState(() => _show = !_show),
            child: Row(children: [
              Expanded(child: Text(_show ? _word! : '••••••••', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.label, letterSpacing: _show ? 0 : 4))),
              Icon(_show ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye_fill, color: p.secondary),
            ]),
          ),
          RoundRow([
            RoundBtn(
              icon: CupertinoIcons.chat_bubble_fill, label: 'Enviar a un contacto', color: AC.blue,
              onTap: s.contacts.isEmpty
                  ? null
                  : () async {
                      final ph = '${s.contacts.first['phone']}'.replaceAll(RegExp(r'[^0-9+]'), '');
                      await launchUrl(Uri.parse('sms:$ph?body=${Uri.encodeComponent('Nuestra palabra clave de seguridad es: $_word')}'));
                    },
            ),
            RoundBtn(
              icon: CupertinoIcons.trash_fill, label: 'Borrar', color: AC.red,
              onTap: () async {
                await _sp?.remove('codeword');
                if (mounted) setState(() { _word = null; _show = false; });
              },
            ),
          ]),
        ],
        SectionLabel(_word == null ? 'Crear palabra' : 'Cambiar palabra'),
        Card2(
          child: Column(children: [
            TextField(controller: _c, maxLength: 30, decoration: const InputDecoration(labelText: 'Palabra o frase corta')),
            const SizedBox(height: 4),
            AppButton(
              label: 'Guardar',
              icon: CupertinoIcons.check_mark,
              onPressed: () async {
                final w = _c.text.trim();
                if (w.length < 3) {
                  toast(context, 'Usa al menos 3 letras');
                  return;
                }
                await _sp?.setString('codeword', w);
                _c.clear();
                if (mounted) setState(() => _word = w);
              },
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text('Se guarda solo en tu teléfono; AEGIS no la sube a ningún servidor.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.secondary)),
      ]),
    );
  }
}
