import 'dart:math';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../sync/sync_service.dart';
import 'theme.dart';
import 'widgets.dart';

const _roleLabel = {
  'SUPER_ADMIN': 'Super admin', 'ADMIN': 'Admin', 'OPERADOR': 'Operador', 'SOPORTE': 'Soporte',
  'USER_NORMAL': 'Normal', 'USER_PREMIUM': 'Premium',
};

/// Contraseña temporal legible (sin caracteres ambiguos) con letras y números.
String genTempPassword() {
  const a = 'abcdefghjkmnpqrstuvwxyz', b = 'ABCDEFGHJKMNPQRSTUVWXYZ', n = '23456789';
  final r = Random.secure();
  String pick(String s) => s[r.nextInt(s.length)];
  final chars = [for (var i = 0; i < 4; i++) pick(a), for (var i = 0; i < 3; i++) pick(b), for (var i = 0; i < 3; i++) pick(n)]..shuffle(r);
  return chars.join();
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>>? _users;
  String? _err;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = await Api.adminUsers();
    if (!mounted) return;
    setState(() {
      _users = u;
      _err = u == null ? 'No se pudo cargar la lista. Revisa tu conexión o tus permisos.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = context.watch<AppState>();
    final list = [for (final u in (_users ?? const <Map<String, dynamic>>[])) if (_q.isEmpty || '${u['email']}'.toLowerCase().contains(_q.toLowerCase())) u];
    return Page2(
      title: 'Usuarios',
      subtitle: s.role == 'SUPER_ADMIN' ? 'Administración' : 'Gestión de cuentas',
      trailing: IconButton.filled(
        onPressed: () => _create(context),
        icon: const Icon(CupertinoIcons.person_add_solid),
        style: IconButton.styleFrom(backgroundColor: AC.blue),
      ),
      children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(CupertinoIcons.search, size: 20)),
        ),
        const SizedBox(height: 14),
        if (_err != null)
          Card2(child: Column(children: [Text(_err!, style: const TextStyle(color: AC.red)), TextButton(onPressed: _load, child: const Text('Reintentar'))]))
        else if (_users == null)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator.adaptive()))
        else if (list.isEmpty)
          Card2(child: Text('No hay usuarios.', style: TextStyle(color: p.secondary)))
        else
          Group(children: [
            for (final u in list)
              InkWell(
                onTap: () => _manage(context, u),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: u['is_active'] == true ? AC.blue : AC.gray,
                      child: Text(('${u['email']}').isEmpty ? '?' : ('${u['email']}')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${u['email']}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: p.label)),
                        Text([
                          _roleLabel[u['role']] ?? '${u['role']}',
                          if (u['is_active'] != true) 'suspendido',
                          if (u['must_change_password'] == true) 'contraseña temporal',
                        ].join(' · '), style: TextStyle(fontSize: 13, color: u['is_active'] == true ? p.secondary : AC.red)),
                      ]),
                    ),
                    Icon(CupertinoIcons.chevron_right, size: 15, color: p.secondary),
                  ]),
                ),
              ),
          ]),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final email = TextEditingController(), phone = TextEditingController(), pw = TextEditingController(text: genTempPassword());
    var role = 'USER_NORMAL';
    final isSuper = context.read<AppState>().role == 'SUPER_ADMIN';
    String? err;
    var busy = false;
    await showSheet<void>(context, (c) => StatefulBuilder(builder: (c, set) {
          final p = Pal.of(c);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Nueva cuenta', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(height: 4),
            Text('Entregas el usuario y la contraseña temporal; al entrar tendrá que cambiarla.', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 12),
            TextField(controller: email, autocorrect: false, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'Correo del usuario')),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Teléfono (opcional)')),
            const SizedBox(height: 10),
            TextField(
              controller: pw,
              decoration: InputDecoration(hintText: 'Contraseña temporal', suffixIcon: IconButton(icon: const Icon(CupertinoIcons.arrow_2_circlepath), onPressed: () => set(() => pw.text = genTempPassword()))),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final r in ['USER_NORMAL', 'USER_PREMIUM', if (isSuper) 'ADMIN'])
                ChoiceChip(label: Text(_roleLabel[r]!), selected: role == r, onSelected: (_) => set(() => role = r)),
            ]),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: AC.red))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: busy ? null : () async {
                if (email.text.trim().length < 5 || pw.text.length < 8) { set(() => err = 'Escribe un correo válido y una contraseña de 8+ caracteres.'); return; }
                set(() { busy = true; err = null; });
                final e = await Api.adminCreate(email.text.trim(), pw.text, role, phone.text.trim());
                if (e != null) { set(() { busy = false; err = errText(e); }); return; }
                if (c.mounted) Navigator.pop(c);
                if (context.mounted) await _showCredentials(context, email.text.trim(), pw.text);
                _load();
              },
              child: Text(busy ? 'Creando…' : 'Crear cuenta'),
            ),
          ]);
        }));
  }

  Future<void> _showCredentials(BuildContext context, String user, String pw) => showSheet<void>(context, (c) {
        final p = Pal.of(c);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(CupertinoIcons.checkmark_seal_fill, color: AC.green, size: 48),
          Text('Cuenta lista', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.label)),
          const SizedBox(height: 6),
          Text('Compártelo por un canal seguro. Esta contraseña no se vuelve a mostrar.', textAlign: TextAlign.center, style: TextStyle(color: p.secondary)),
          const SizedBox(height: 12),
          Group(children: [
            Row2(icon: CupertinoIcons.person_fill, color: AC.blue, title: 'Usuario', value: user),
            Row2(icon: CupertinoIcons.lock_fill, color: AC.orange, title: 'Contraseña temporal', value: pw),
          ]),
          FilledButton.icon(
              onPressed: () { Clipboard.setData(ClipboardData(text: 'Usuario: $user\nContraseña temporal: $pw')); toast(c, 'Copiado'); },
              icon: const Icon(CupertinoIcons.doc_on_doc), label: const Text('Copiar datos')),
        ]);
      });

  Future<void> _manage(BuildContext context, Map<String, dynamic> u) async {
    final me = context.read<AppState>();
    final id = u['id'] as String;
    final isUser = u['role'] == 'USER_NORMAL' || u['role'] == 'USER_PREMIUM';
    final protected = u['role'] == 'SUPER_ADMIN';
    Future<void> act(BuildContext c, String action, {Object? body, String ok = 'Hecho'}) async {
      final e = await Api.adminAction(id, action, body);
      if (c.mounted) Navigator.pop(c);
      if (context.mounted) toast(context, e == null ? ok : errText(e));
      _load();
    }

    await showSheet<void>(context, (c) {
      final p = Pal.of(c);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${u['email']}', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.label)),
        Text('${_roleLabel[u['role']] ?? u['role']}${u['phone'] != null ? ' · ${u['phone']}' : ''}', textAlign: TextAlign.center, style: TextStyle(color: p.secondary)),
        const SizedBox(height: 14),
        if (isUser)
          Segmented<String>(
            value: u['role'] as String,
            items: const {'USER_NORMAL': 'Normal', 'USER_PREMIUM': 'Premium'},
            onChanged: (v) => act(c, 'plan', body: {'plan': v == 'USER_PREMIUM' ? 'PREMIUM' : 'NORMAL'}, ok: 'Plan cambiado'),
          ),
        const SizedBox(height: 12),
        Group(children: [
          Row2(
            icon: CupertinoIcons.lock_rotation, color: AC.orange, title: 'Restablecer contraseña', subtitle: 'Genera una temporal', chevron: true,
            onTap: () async {
              final t = genTempPassword();
              final e = await Api.adminAction(id, 'reset-password', {'temp_password': t});
              if (c.mounted) Navigator.pop(c);
              if (!context.mounted) return;
              if (e == null) {
                await _showCredentials(context, '${u['email']}', t);
              } else {
                toast(context, errText(e));
              }
            },
          ),
          if (!protected && u['is_active'] == true)
            Row2(icon: CupertinoIcons.pause_circle_fill, color: AC.red, title: 'Suspender cuenta', chevron: true, onTap: () => act(c, 'suspend', ok: 'Cuenta suspendida'))
          else if (!protected)
            Row2(icon: CupertinoIcons.play_circle_fill, color: AC.green, title: 'Reactivar cuenta', chevron: true, onTap: () => act(c, 'activate', ok: 'Cuenta reactivada')),
          if (!protected && u['email'] != me.loginName)
            Row2(
              icon: CupertinoIcons.delete_solid, color: AC.red, title: 'Eliminar cuenta', chevron: true,
              onTap: () async {
                final sure = await showDialog<bool>(
                  context: c,
                  builder: (d) => AlertDialog(
                    title: const Text('¿Eliminar cuenta?'),
                    content: Text('${u['email']} ya no podrá entrar.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Eliminar', style: TextStyle(color: AC.red)))],
                  ),
                );
                if (sure == true && c.mounted) await act(c, 'delete', ok: 'Cuenta eliminada');
              },
            ),
        ]),
      ]);
    });
  }
}
