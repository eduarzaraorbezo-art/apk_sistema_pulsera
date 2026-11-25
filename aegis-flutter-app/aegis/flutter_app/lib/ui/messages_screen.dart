import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Mensajes rápidos: un toque y se envía a todos tus contactos con tu ubicación.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  String? _sending;
  Future<List<Map<String, dynamic>>>? _hist;

  @override
  void initState() {
    super.initState();
    _hist = context.read<AppState>().messageHistory();
  }

  Future<void> _send(AppState s, Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('¿Enviar a tus contactos?'),
        content: Text('"${t['text']}"\n\nSe enviará a ${s.contacts.length} contacto(s) con tu ubicación.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 40)), onPressed: () => Navigator.pop(d, true), child: const Text('Enviar'))],
      ),
    );
    if (ok != true) return;
    setState(() => _sending = t['id'] as String);
    final o = await s.sendTemplate(t['id'] as String);
    if (!mounted) return;
    setState(() { _sending = null; _hist = s.messageHistory(); });
    HapticFeedback.mediumImpact();
    toast(context, o.server ? 'Enviado a tus contactos' : (o.composer ? 'Se abrió tu app de mensajes: pulsa enviar' : o.text));
  }

  Future<void> _edit(AppState s, {Map<String, dynamic>? t}) async {
    final ctl = TextEditingController(text: t?['text'] as String? ?? '');
    final res = await showSheet<String>(context, (c) {
      final p = Pal.of(c);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t == null ? 'Nuevo mensaje' : 'Editar mensaje', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
        const SizedBox(height: 12),
        TextField(controller: ctl, maxLength: 160, maxLines: 3, autofocus: true, decoration: const InputDecoration(hintText: 'Escribe el mensaje')),
        FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Guardar')),
        if (t != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Eliminar', style: TextStyle(color: AC.red))),
      ]);
    });
    if (res == null) return;
    final list = s.templates;
    if (res == 'delete') {
      list.removeWhere((x) => x['id'] == t!['id']);
      // los gestos que apuntaban a este mensaje pasan a "ninguna"
      final g = Map<String, dynamic>.from(s.settings['gestures'] as Map);
      for (final k in g.keys.toList()) {
        if ((g[k] as Map)['message_id'] == t!['id']) g[k] = {'action': 'none'};
      }
      await _save(s, {'templates': list, 'gestures': g});
    } else if (ctl.text.trim().isNotEmpty) {
      if (t == null) {
        if (list.length >= 12) { toast(context, 'Máximo 12 mensajes'); return; }
        final ids = {for (final x in list) x['id']};
        var n = list.length + 1;
        while (ids.contains('m$n')) { n++; }
        list.add({'id': 'm$n', 'text': ctl.text.trim()});
      } else {
        final i = list.indexWhere((x) => x['id'] == t['id']);
        list[i] = {'id': t['id'], 'text': ctl.text.trim()};
      }
      await _save(s, {'templates': list});
    }
  }

  Future<void> _save(AppState s, Map<String, dynamic> change) async {
    final e = await s.saveSettings(change);
    if (mounted && e != null) toast(context, 'Guardado en el teléfono; no se pudo respaldar (${errText(e)})');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensajes rápidos'),
        actions: [IconButton(onPressed: () => _edit(s), icon: const Icon(CupertinoIcons.add))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Text('Toca un mensaje para enviarlo a tus contactos con tu ubicación. También puedes asignarlos a los botones de la pulsera.', style: TextStyle(color: p.secondary)),
        const SizedBox(height: 14),
        if (s.contacts.isEmpty) Card2(color: AC.orange.withOpacity(0.14), child: const Text('Aún no tienes contactos: agrégalos en la pestaña Contactos.')),
        Group(children: [
          for (final t in s.templates)
            InkWell(
              onTap: _sending == null ? () => _send(s, t) : null,
              onLongPress: () => _edit(s, t: t),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  const IconBadge(CupertinoIcons.paperplane_fill, AC.blue),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${t['text']}', style: TextStyle(fontSize: 16, color: p.label))),
                  if (_sending == t['id']) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) else IconButton(icon: Icon(CupertinoIcons.pencil, size: 18, color: p.secondary), onPressed: () => _edit(s, t: t)),
                ]),
              ),
            ),
        ]),
        const SectionLabel('Enviados recientemente'),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _hist,
          builder: (_, snap) {
            final h = snap.data ?? const [];
            if (h.isEmpty) return Card2(child: Text(snap.connectionState == ConnectionState.waiting ? 'Cargando…' : 'Todavía no has enviado mensajes desde el servidor.', style: TextStyle(color: p.secondary)));
            return Group(children: [
              for (final m in h.take(8))
                Row2(
                  icon: m['status'] == 'SENT' ? CupertinoIcons.checkmark_circle_fill : (m['status'] == 'FAILED' ? CupertinoIcons.xmark_circle_fill : CupertinoIcons.clock_fill),
                  color: m['status'] == 'SENT' ? AC.green : (m['status'] == 'FAILED' ? AC.red : AC.gray),
                  title: '${m['contact']}', subtitle: '${m['body']}',
                ),
            ]);
          },
        ),
        Padding(padding: const EdgeInsets.all(8), child: Text('Estado "registrado" = el servidor aún no tiene un proveedor de SMS configurado; en ese caso AEGIS abre tu app de mensajes para que lo envíes tú.', style: TextStyle(fontSize: 12, color: p.secondary))),
      ]),
    );
  }
}
