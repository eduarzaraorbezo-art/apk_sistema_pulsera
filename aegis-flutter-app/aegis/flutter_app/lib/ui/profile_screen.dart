import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../sync/sync_service.dart' show apiBase;
import 'auth_screens.dart';
import 'activity_screen.dart';
import 'band_screen.dart';
import 'evidence_screen.dart';
import 'messages_screen.dart';
import 'theme.dart';
import 'widgets.dart';

const _blood = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
const _roleName = {
  'SUPER_ADMIN': 'Super administrador', 'ADMIN': 'Administrador', 'OPERADOR': 'Operador', 'SOPORTE': 'Soporte',
  'USER_NORMAL': 'Plan Normal', 'USER_PREMIUM': 'Plan Premium',
};

/// Ficha médica de emergencia: lo que un socorrista necesita ver.
class MedicalIdSheet extends StatelessWidget {
  const MedicalIdSheet({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    String v(String k) {
      final x = profile[k];
      return (x == null || '$x'.trim().isEmpty) ? '—' : '$x';
    }

    final age = profile['birth_year'] is int ? '${DateTime.now().year - (profile['birth_year'] as int)} años' : '—';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(CupertinoIcons.heart_text_square_fill, color: AC.red, size: 44),
      Text('Ficha médica', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.label)),
      const SizedBox(height: 12),
      Group(children: [
        Row2(icon: CupertinoIcons.person_fill, color: AC.blue, title: 'Nombre', value: v('full_name')),
        Row2(icon: CupertinoIcons.calendar, color: AC.gray, title: 'Edad', value: age),
        Row2(icon: CupertinoIcons.drop_fill, color: AC.red, title: 'Grupo sanguíneo', value: v('blood_type')),
        Row2(icon: CupertinoIcons.exclamationmark_triangle_fill, color: AC.orange, title: 'Alergias', value: v('allergies')),
        Row2(icon: CupertinoIcons.heart_fill, color: AC.pink, title: 'Condiciones', value: v('conditions')),
        Row2(icon: CupertinoIcons.capsule_fill, color: AC.teal, title: 'Medicación', value: v('medications')),
        Row2(icon: CupertinoIcons.doc_text_fill, color: AC.purple, title: 'Notas', value: v('notes')),
      ]),
    ]);
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final fullName = (s.profile['full_name'] as String?)?.trim() ?? '';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : (s.loginName.isNotEmpty ? s.loginName[0].toUpperCase() : '?');
    return Page2(
      title: 'Perfil',
      children: [
        Card2(
          onTap: () => _photo(context, s),
          child: Row(children: [
            Stack(children: [
              AvatarView(bytes: s.avatar, initial: initial, radius: 36),
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: AC.blue, shape: BoxShape.circle, border: Border.all(color: p.card, width: 2)),
                  child: const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 12),
                ),
              ),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fullName.isNotEmpty ? fullName : (s.loginName.isEmpty ? 'Tu nombre' : s.loginName), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: p.label)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: (s.isPremium ? AC.orange : AC.blue).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(_roleName[s.role] ?? s.role, style: TextStyle(color: s.isPremium ? AC.orange : AC.blue, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ]),
            ),
          ]),
        ),
        const SectionLabel('Cuenta'),
        Group(children: [
          Row2(icon: CupertinoIcons.person_crop_circle_fill, color: AC.blue, title: 'Usuario', value: s.loginName),
          if (!s.isAdmin) Row2(icon: CupertinoIcons.person_fill, color: AC.teal, title: 'Nombre completo', value: fullName.isEmpty ? 'Agregar' : fullName, chevron: true, onTap: () => _editName(context, s)),
          Row2(icon: CupertinoIcons.phone_fill, color: AC.green, title: 'Teléfono', value: s.phone ?? 'Agregar', chevron: true, onTap: () => _editPhone(context, s)),
          Row2(icon: CupertinoIcons.lock_fill, color: AC.orange, title: 'Cambiar contraseña', chevron: true, onTap: () => showSheet<void>(context, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Cambiar contraseña', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Pal.of(c).label)),
                const SizedBox(height: 12),
                PasswordForm(onDone: () { Navigator.pop(c); toast(context, 'Contraseña actualizada'); }),
              ]))),
        ]),
        if (!s.isAdmin) ...[
          const SectionLabel('Mi pulsera'),
          Group(children: [
            Row2(icon: CupertinoIcons.bluetooth, color: AC.blue, title: 'Pulsera y botones', subtitle: 'Gestos, caídas, buscar pulsera', chevron: true, onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const BandScreen()))),
            Row2(icon: CupertinoIcons.clock_fill, color: AC.orange, title: 'Actividad', subtitle: 'Gestos y alertas de la pulsera', chevron: true, onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const ActivityScreen()))),
            Row2(icon: CupertinoIcons.paperplane_fill, color: AC.green, title: 'Mensajes rápidos', subtitle: '${s.templates.length} mensajes', chevron: true, onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const MessagesScreen()))),
          ]),
          const SectionLabel('Comunidad'),
        Group(children: [
          Row2(
            icon: CupertinoIcons.person_3_fill, color: AC.green, title: 'Modo ayudante',
            subtitle: 'Recibir avisos de personas en peligro a menos de 3 km',
            trailing: Switch.adaptive(value: s.settings['helper_mode'] != false, onChanged: (v) => s.saveSettings({'helper_mode': v})),
          ),
          Row2(
            icon: CupertinoIcons.dot_radiowaves_left_right, color: AC.red, title: 'Avisar a ayudantes en mi SOS',
            subtitle: 'Verán tu nombre de pila y tu ubicación mientras dure la emergencia',
            trailing: Switch.adaptive(value: s.settings['community_alerts'] != false, onChanged: (v) => s.saveSettings({'community_alerts': v})),
          ),
        ]),
        const SectionLabel('Evidencia'),
        Group(children: [
          Row2(
            icon: CupertinoIcons.mic_fill, color: AC.red, title: 'Grabación automática',
            subtitle: s.canAutoRecord ? 'Graba audio en un SOS, caída o manipulación' : 'Solo con plan Premium',
            trailing: Switch.adaptive(value: s.canAutoRecord && s.settings['auto_record'] != false, onChanged: s.canAutoRecord ? (v) => s.saveSettings({'auto_record': v}) : null),
          ),
          Row2(icon: CupertinoIcons.folder_fill, color: AC.orange, title: 'Mis evidencias', subtitle: 'Audios y fotos guardados', chevron: true, onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const EvidenceScreen()))),
        ]),
        const SectionLabel('Salud'),
          Group(children: [
            Row2(icon: CupertinoIcons.heart_text_square_fill, color: AC.red, title: 'Ficha médica', subtitle: 'Visible desde Inicio para socorristas', chevron: true, onTap: () => _editMedical(context, s)),
            Row2(icon: CupertinoIcons.waveform_path_ecg, color: AC.pink, title: 'Rango de pulsaciones', value: '${s.hrMin}–${s.hrMax}', chevron: true, onTap: () => _editRange(context, s)),
          ]),
        ],
        const SectionLabel('Apariencia'),
        Card2(
          child: Segmented<ThemeMode>(
            value: s.themeMode,
            items: const {ThemeMode.system: 'Sistema', ThemeMode.light: 'Claro', ThemeMode.dark: 'Oscuro'},
            onChanged: s.setThemeMode,
          ),
        ),
        if (!s.isAdmin) ...[
          const SectionLabel('Sincronización'),
          Group(children: [
            Row2(icon: CupertinoIcons.cloud_fill, color: AC.blue, title: 'Estado', value: s.syncLabel == 'ONLINE' ? 'Al día' : (s.syncLabel == 'OFFLINE' ? 'Sin conexión' : '${s.pending} pendientes')),
            Row2(
              icon: CupertinoIcons.arrow_2_circlepath, color: AC.green, title: 'Sincronizar ahora',
              subtitle: s.lastSync == 0 ? 'Aún no se ha sincronizado' : 'Última: ${fmtDate(s.lastSync)}',
              chevron: true,
              onTap: () async {
                await s.syncNow();
                if (context.mounted) toast(context, s.pending == 0 ? 'Todo sincronizado' : 'Quedan ${s.pending} pendientes');
              },
            ),
          ]),
        ],
        const SectionLabel('Acerca de'),
        Group(children: [
          const Row2(icon: CupertinoIcons.shield_fill, color: AC.gray, title: 'AEGIS Smart Safety Band', value: 'v0.3'),
          Row2(icon: CupertinoIcons.link, color: AC.gray, title: 'Servidor', value: apiBase.replaceFirst('https://', '')),
        ]),
        const SizedBox(height: 4),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: AC.red, minimumSize: const Size.fromHeight(50), side: BorderSide(color: p.separator), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () => _logout(context, s),
          child: const Text('Cerrar sesión', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('AEGIS ayuda a pedir auxilio, pero no sustituye a los servicios de emergencia ni los contacta por sí mismo.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.secondary)),
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context, AppState s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: Text(s.pending > 0 ? 'Tienes ${s.pending} elementos sin sincronizar. Si cierras sesión con otra cuenta, se descartarán.' : 'Dejarás de recibir los avisos de tu pulsera en este teléfono.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cerrar sesión', style: TextStyle(color: AC.red)))],
      ),
    );
    if (ok == true) await s.signOut();
  }

  Future<void> _photo(BuildContext context, AppState s) async {
    final src = await showSheet<Object>(context, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Foto de perfil', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Pal.of(c).label)),
          const SizedBox(height: 12),
          Group(children: [
            Row2(icon: CupertinoIcons.photo_fill, color: AC.blue, title: 'Elegir de la galería', onTap: () => Navigator.pop(c, ImageSource.gallery)),
            Row2(icon: CupertinoIcons.camera_fill, color: AC.green, title: 'Tomar foto', onTap: () => Navigator.pop(c, ImageSource.camera)),
            if (s.avatar != null) Row2(icon: CupertinoIcons.delete_solid, color: AC.red, title: 'Quitar foto', onTap: () => Navigator.pop(c, 'remove')),
          ]),
        ]));
    if (src == null) return;
    if (src == 'remove') {
      await s.removeAvatar();
      return;
    }
    try {
      final x = await ImagePicker().pickImage(source: src as ImageSource, maxWidth: 480, maxHeight: 480, imageQuality: 75);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final mime = x.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final e = await s.setAvatar(bytes, mime);
      if (context.mounted && e != null) toast(context, errText(e));
    } catch (_) {
      if (context.mounted) toast(context, 'No se pudo abrir la cámara o la galería.');
    }
  }

  Future<void> _editName(BuildContext context, AppState s) async {
    final ctl = TextEditingController(text: (s.profile['full_name'] as String?) ?? '');
    final ok = await showSheet<bool>(context, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nombre completo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Pal.of(c).label)),
          const SizedBox(height: 12),
          TextField(controller: ctl, textCapitalization: TextCapitalization.words, autofocus: true, decoration: const InputDecoration(hintText: 'Tu nombre')),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ]));
    if (ok == true) await s.saveProfile({'full_name': ctl.text.trim().isEmpty ? null : ctl.text.trim()});
  }

  Future<void> _editPhone(BuildContext context, AppState s) async {
    final ctl = TextEditingController(text: s.phone ?? '');
    final ok = await showSheet<bool>(context, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Teléfono', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Pal.of(c).label)),
          const SizedBox(height: 4),
          Text('Con código de país, por ejemplo +51987654321.', style: TextStyle(color: Pal.of(c).secondary)),
          const SizedBox(height: 12),
          TextField(controller: ctl, keyboardType: TextInputType.phone, autofocus: true, decoration: const InputDecoration(hintText: '+51…')),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ]));
    if (ok != true) return;
    final e = await s.savePhone(ctl.text);
    if (context.mounted && e != null) toast(context, errText(e));
  }

  Future<void> _editMedical(BuildContext context, AppState s) async {
    final pr = s.profile;
    String t(String k) => (pr[k] ?? '').toString();
    final name = TextEditingController(text: t('full_name')), year = TextEditingController(text: t('birth_year'));
    final all = TextEditingController(text: t('allergies')), cond = TextEditingController(text: t('conditions'));
    final med = TextEditingController(text: t('medications')), notes = TextEditingController(text: t('notes'));
    String? blood = _blood.contains(pr['blood_type']) ? pr['blood_type'] as String : null;
    final saved = await showSheet<bool>(context, (c) => StatefulBuilder(builder: (c, set) {
          final p = Pal.of(c);
          Widget f(String h, TextEditingController ct, {TextInputType? k}) => Padding(
              padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: ct, keyboardType: k, decoration: InputDecoration(hintText: h)));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Ficha médica', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.label)),
            const SizedBox(height: 4),
            Text('Solo tú la ves. Sirve para dársela a un socorrista.', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 12),
            f('Nombre completo', name),
            f('Año de nacimiento', year, k: TextInputType.number),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final b in _blood) ChoiceChip(label: Text(b), selected: blood == b, onSelected: (v) => set(() => blood = v ? b : null)),
            ]),
            const SizedBox(height: 10),
            f('Alergias', all),
            f('Condiciones médicas', cond),
            f('Medicación', med),
            f('Notas', notes),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ]);
        }));
    if (saved != true) return;
    final y = int.tryParse(year.text.trim());
    String? n(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final ok = await s.saveProfile({
      'full_name': n(name), 'birth_year': (y != null && y >= 1900 && y <= DateTime.now().year) ? y : null, 'blood_type': blood,
      'allergies': n(all), 'conditions': n(cond), 'medications': n(med), 'notes': n(notes),
    });
    if (context.mounted) toast(context, ok ? 'Guardado y respaldado' : 'Guardado en el teléfono; se respaldará luego');
  }

  Future<void> _editRange(BuildContext context, AppState s) async {
    var lo = s.hrMin.toDouble(), hi = s.hrMax.toDouble();
    final ok = await showSheet<bool>(context, (c) => StatefulBuilder(builder: (c, set) {
          final p = Pal.of(c);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Rango de pulsaciones', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.label)),
            Text('Te avisamos si te sales de este rango varias lecturas seguidas. Pregunta a tu médico qué rango te conviene.', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 14),
            Text('Mínimo: ${lo.round()} lpm', style: TextStyle(color: p.label)),
            Slider.adaptive(value: lo, min: 30, max: 90, onChanged: (v) => set(() => lo = v)),
            Text('Máximo: ${hi.round()} lpm', style: TextStyle(color: p.label)),
            Slider.adaptive(value: hi, min: 100, max: 200, onChanged: (v) => set(() => hi = v)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ]);
        }));
    if (ok == true) await s.saveProfile({'hr_min': lo.round(), 'hr_max': hi.round()});
  }
}
