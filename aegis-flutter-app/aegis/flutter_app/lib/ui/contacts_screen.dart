import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

const _colors = [AC.blue, AC.green, AC.orange, AC.purple, AC.pink, AC.teal];

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    return Page2(
      title: 'Contactos',
      subtitle: 'Tu red de confianza',
      trailing: IconButton.filled(
        onPressed: () => _add(context, s),
        icon: const Icon(CupertinoIcons.add),
        style: IconButton.styleFrom(backgroundColor: AC.blue),
      ),
      children: [
        if (s.contacts.isEmpty)
          Card2(
            child: Column(children: [
              const Icon(CupertinoIcons.person_2_fill, size: 44, color: AC.gray),
              const SizedBox(height: 8),
              Text('Aún no tienes contactos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.label)),
              Text('Agrega a quienes deben recibir tu alerta y tu ubicación.', textAlign: TextAlign.center, style: TextStyle(color: p.secondary)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => _add(context, s), child: const Text('Agregar contacto')),
            ]),
          )
        else ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AC.green),
            onPressed: () async { if (!await s.alertContacts() && context.mounted) toast(context, 'No se pudo abrir mensajes'); },
            icon: const Icon(CupertinoIcons.location_fill),
            label: const Text('Compartir mi ubicación con todos'),
          ),
          const SizedBox(height: 14),
          Group(children: [
            for (var i = 0; i < s.contacts.length; i++)
              Dismissible(
                key: ValueKey(s.contacts[i]['id']),
                direction: DismissDirection.endToStart,
                background: Container(color: AC.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(CupertinoIcons.delete, color: Colors.white)),
                onDismissed: (_) => s.removeContact(s.contacts[i]['id'] as int),
                child: Container(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _actions(context, '${s.contacts[i]['name']}', '${s.contacts[i]['phone']}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 20, backgroundColor: _colors[i % _colors.length],
                          child: Text(('${s.contacts[i]['name']}').trim().isEmpty ? '?' : ('${s.contacts[i]['name']}').trim()[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${s.contacts[i]['name']}', style: TextStyle(fontSize: 17, color: p.label)),
                            Text('${s.contacts[i]['phone']}', style: TextStyle(fontSize: 13, color: p.secondary)),
                          ]),
                        ),
                        Icon(CupertinoIcons.ellipsis, color: p.secondary),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Desliza a la izquierda para quitar. Toca un contacto para llamar o escribirle.', style: TextStyle(fontSize: 12, color: p.secondary))),
        ],
      ],
    );
  }

  String _clean(String n) => n.replaceAll(RegExp(r'[^0-9+]'), '');

  void _actions(BuildContext context, String name, String phone) {
    showSheet(context, (c) {
      final p = Pal.of(c);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
        Text(phone, textAlign: TextAlign.center, style: TextStyle(color: p.secondary)),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: () { launchUrl(Uri.parse('tel:${_clean(phone)}')); Navigator.pop(c); }, icon: const Icon(CupertinoIcons.phone_fill), label: const Text('Llamar')),
        const SizedBox(height: 8),
        FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AC.green),
            onPressed: () { launchUrl(Uri.parse('sms:${_clean(phone)}')); Navigator.pop(c); },
            icon: const Icon(CupertinoIcons.chat_bubble_fill), label: const Text('Enviar mensaje')),
      ]);
    });
  }

  Future<void> _add(BuildContext context, AppState s) async {
    final name = TextEditingController(), phone = TextEditingController();
    final ok = await showSheet<bool>(context, (c) {
      final p = Pal.of(c);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Nuevo contacto', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.label)),
        const SizedBox(height: 12),
        TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Nombre')),
        const SizedBox(height: 10),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Teléfono (con código de país)')),
        const SizedBox(height: 14),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
      ]);
    });
    if (ok != true) return;
    if (name.text.trim().isEmpty || _clean(phone.text).length < 6) {
      if (context.mounted) toast(context, 'Escribe un nombre y un teléfono válido');
      return;
    }
    await s.addContact(name.text.trim(), phone.text.trim());
  }
}
