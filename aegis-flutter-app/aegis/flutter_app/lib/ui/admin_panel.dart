import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../sync/sync_service.dart';
import 'theme.dart';
import 'widgets.dart';

/// Carga una vez, permite tirar para refrescar y muestra error con reintento.
class _Loader extends StatefulWidget {
  const _Loader({required this.title, this.subtitle, required this.load, required this.builder, this.trailing});
  final String title;
  final String? subtitle;
  final Future<Map<String, dynamic>?> Function() load;
  final List<Widget> Function(BuildContext, Map<String, dynamic>, Future<void> Function()) builder;
  final Widget? trailing;
  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  Map<String, dynamic>? _d;
  bool _failed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final d = await widget.load();
    if (!mounted) return;
    setState(() {
      _d = d ?? _d;
      _failed = d == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator.adaptive(
        onRefresh: _reload,
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: p.label, letterSpacing: -0.5)),
                  if (widget.subtitle != null) Text(widget.subtitle!, style: TextStyle(fontSize: 15, color: p.secondary)),
                ]),
              ),
              if (widget.trailing != null) widget.trailing!,
            ]),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator.adaptive()))
            else if (_d == null)
              Card2(child: Column(children: [
                const Text('No se pudo cargar. Revisa tu conexión o tus permisos.', style: TextStyle(color: AC.red)),
                const SizedBox(height: 8),
                AppButton(label: 'Reintentar', compact: true, onPressed: () { setState(() => _loading = true); _reload(); }),
              ]))
            else ...[
              if (_failed) const Padding(padding: EdgeInsets.only(bottom: 8), child: Pill('Sin conexión · datos anteriores', icon: CupertinoIcons.exclamationmark_triangle_fill, color: AC.orange)),
              ...widget.builder(context, _d!, _reload),
            ],
          ],
        ),
      ),
    );
  }
}

String _mb(num b) => b >= 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).toStringAsFixed(0)} KB';
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

// =====================================================================================================
// PANEL (dashboard)
// =====================================================================================================
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>();
    return _Loader(
      title: 'Panel',
      subtitle: me.role == 'SUPER_ADMIN' ? 'Control total del sistema' : 'Resumen de la plataforma',
      load: Api.adminStats,
      builder: (context, d, reload) {
        final p = Pal.of(context);
        final u = Map<String, dynamic>.from(d['users'] as Map);
        final e = Map<String, dynamic>.from(d['emergencies'] as Map);
        final ev = Map<String, dynamic>.from(d['evidence'] as Map);
        final m = Map<String, dynamic>.from(d['messages_24h'] as Map);
        final cm = Map<String, dynamic>.from(d['community'] as Map);
        final perDay = [for (final x in (e['per_day'] as List)) Map<String, dynamic>.from(x as Map)];
        final top = perDay.map((x) => _i(x['count'])).fold<int>(1, (a, b) => a > b ? a : b);
        final roles = Map<String, dynamic>.from(u['by_role'] as Map);
        final active = _i(e['active']);
        return [
          Container(
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: active > 0 ? const [Color(0xFFFF375F), Color(0xFFFF9F0A)] : const [Color(0xFF2563EB), Color(0xFF7C3AED)]),
              boxShadow: [BoxShadow(color: (active > 0 ? AC.red : AC.blue).withOpacity(0.35), blurRadius: 22, offset: const Offset(0, 8))],
            ),
            child: Row(children: [
              Icon(active > 0 ? CupertinoIcons.exclamationmark_shield_fill : CupertinoIcons.checkmark_shield_fill, color: Colors.white, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(active > 0 ? '$active emergencia${active == 1 ? '' : 's'} activa${active == 1 ? '' : 's'}' : 'Todo en calma', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('${_i(e['last_24h'])} en las últimas 24 h · ${_i(e['total'])} en total', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13.5)),
                ]),
              ),
            ]),
          ),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.55,
            children: [
              StatTile(icon: CupertinoIcons.person_3_fill, color: AC.blue, label: 'Usuarios', value: '${_i(u['total'])}', unit: '${_i(u['active'])} activos'),
              StatTile(icon: CupertinoIcons.star_fill, color: AC.orange, label: 'Premium', value: '${_i(u['premium'])}', unit: '+${_i(u['new_7d'])} en 7 d'),
              StatTile(icon: CupertinoIcons.cloud_fill, color: AC.teal, label: 'Evidencias', value: '${_i(ev['total'])}', unit: _mb(_i(ev['bytes']))),
              StatTile(icon: CupertinoIcons.chat_bubble_2_fill, color: AC.green, label: 'Mensajes 24 h', value: '${_i(m['total'])}'),
              StatTile(icon: CupertinoIcons.bluetooth, color: AC.purple, label: 'Pulseras', value: '${_i(d['devices'])}'),
              StatTile(icon: CupertinoIcons.map_pin_ellipse, color: AC.pink, label: 'Zonas', value: '${_i(cm['places'])}', unit: '${_i(cm['reported'])} reportadas'),
            ],
          ),
          const SizedBox(height: 14),
          const SectionLabel('Emergencias · 7 días'),
          Card2(
            child: SizedBox(
              height: 130,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final x in perDay)
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${_i(x['count'])}', style: TextStyle(fontSize: 11, color: p.secondary)),
                      const SizedBox(height: 3),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic,
                        height: 8 + 80 * (_i(x['count']) / top), margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AC.red, AC.orange])),
                      ),
                      const SizedBox(height: 5),
                      Text('${x['label']}', style: TextStyle(fontSize: 10, color: p.secondary)),
                    ]),
                  ),
              ]),
            ),
          ),
          const SectionLabel('Cuentas por rol'),
          Card2(
            child: Column(children: [
              for (final r in roles.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 92, child: Text(_roleName(r.key), style: TextStyle(fontSize: 13.5, color: p.label))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(value: _i(r.value) / (_i(u['total']) == 0 ? 1 : _i(u['total'])), minHeight: 10, backgroundColor: p.fill, color: r.key == 'USER_PREMIUM' ? AC.orange : AC.blue),
                      ),
                    ),
                    SizedBox(width: 34, child: Text('${_i(r.value)}', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w700, color: p.label))),
                  ]),
                ),
              const Divider(height: 18),
              Row(children: [
                Expanded(child: Text('Con MFA: ${_i(u['mfa'])}', style: TextStyle(color: p.secondary))),
                Text('Suspendidas: ${_i(u['suspended'])}', style: TextStyle(color: _i(u['suspended']) > 0 ? AC.red : p.secondary)),
              ]),
            ]),
          ),
          const SectionLabel('Evidencias por tipo'),
          Card2(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in Map<String, dynamic>.from(ev['by_kind'] as Map).entries)
                Pill('${k.key}: ${_i((k.value as Map)['count'])} · ${_mb(_i((k.value as Map)['bytes']))}', icon: CupertinoIcons.cloud_fill, color: AC.teal),
              if ((ev['by_kind'] as Map).isEmpty) Text('Aún no hay evidencias.', style: TextStyle(color: p.secondary)),
            ]),
          ),
        ];
      },
    );
  }
}

String _roleName(String r) => const {
      'SUPER_ADMIN': 'Super admin', 'ADMIN': 'Admin', 'OPERADOR': 'Operador', 'SOPORTE': 'Soporte', 'USER_NORMAL': 'Normal', 'USER_PREMIUM': 'Premium',
    }[r] ??
    r;

// =====================================================================================================
// COMUNIDAD (moderación)
// =====================================================================================================
class AdminCommunity extends StatelessWidget {
  const AdminCommunity({super.key});
  @override
  Widget build(BuildContext context) => _Loader(
        title: 'Comunidad',
        subtitle: 'Moderación de zonas marcadas',
        load: Api.adminCommunity,
        builder: (context, d, reload) {
          final p = Pal.of(context);
          final items = [for (final x in (d['items'] as List)) Map<String, dynamic>.from(x as Map)];
          final head = Card2(
            onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const AdminAnnouncements())),
            color: AC.orange.withOpacity(0.14),
            child: Row(children: [
              const Icon(CupertinoIcons.speaker_2_fill, color: AC.orange),
              const SizedBox(width: 12),
              Expanded(child: Text('Avisos globales a usuarios', style: TextStyle(fontWeight: FontWeight.w700, color: p.label))),
              Icon(CupertinoIcons.chevron_right, size: 16, color: p.secondary),
            ]),
          );
          if (items.isEmpty) return [head, Card2(child: Text('No hay zonas marcadas todavía.', style: TextStyle(color: p.secondary)))];
          return [
            head,
            for (final it in items)
              Card2(
                color: _i(it['reports']) > 0 ? AC.red.withOpacity(0.10) : null,
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${it['title']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.label)),
                      if (it['note'] != null) Text('${it['note']}', style: TextStyle(fontSize: 13, color: p.secondary)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, children: [
                        Pill('${it['kind']}', color: AC.blue),
                        Pill('${_i(it['confirms'])} confirmaciones', icon: CupertinoIcons.hand_thumbsup_fill, color: AC.green),
                        if (_i(it['reports']) > 0) Pill('${_i(it['reports'])} reportes', icon: CupertinoIcons.flag_fill, color: AC.red),
                      ]),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.delete_solid, color: AC.red),
                    onPressed: () async {
                      final e = await Api.adminDeletePlace('${it['id']}');
                      if (context.mounted) toast(context, e == null ? 'Zona eliminada' : errText(e));
                      reload();
                    },
                  ),
                ]),
              ),
          ];
        },
      );
}

// =====================================================================================================
// SISTEMA (solo superadmin): estado, planes y auditoría
// =====================================================================================================
class AdminSystem extends StatelessWidget {
  const AdminSystem({super.key});
  @override
  Widget build(BuildContext context) => _Loader(
        title: 'Sistema',
        subtitle: 'Solo superadmin',
        load: Api.adminSystem,
        builder: (context, d, reload) {
          final p = Pal.of(context);
          final ok = d['audit_chain_ok'] == true;
          return [
            Group(children: [
              Row2(icon: CupertinoIcons.cloud_fill, color: AC.blue, title: 'Versión del servidor', value: '${d['version']}'),
              Row2(icon: CupertinoIcons.chat_bubble_fill, color: AC.green, title: 'Envío de mensajes', value: '${d['notify_provider']}', subtitle: d['webhook'] == true ? 'Webhook configurado' : 'Sin webhook'),
              Row2(icon: ok ? CupertinoIcons.checkmark_shield_fill : CupertinoIcons.exclamationmark_triangle_fill, color: ok ? AC.green : AC.red, title: 'Integridad de auditoría', value: ok ? 'Íntegra' : '¡Alterada!', subtitle: '${_i(d['audit_entries'])} registros'),
              Row2(icon: CupertinoIcons.time, color: AC.gray, title: 'Hora del servidor', value: '${d['server_time']}'.replaceFirst('T', ' ').split('.').first),
            ]),
            const SectionLabel('Herramientas'),
            Group(children: [
              Row2(icon: CupertinoIcons.doc_text_search, color: AC.purple, title: 'Registro de auditoría', subtitle: 'Quién hizo qué, con cadena de hashes', chevron: true,
                  onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const AdminAudit()))),
              Row2(icon: CupertinoIcons.slider_horizontal_3, color: AC.orange, title: 'Planes y límites', subtitle: 'Edita lo que incluye Normal y Premium', chevron: true,
                  onTap: () => Navigator.push(context, CupertinoPageRoute<void>(builder: (_) => const PlansScreen()))),
            ]),
            Padding(padding: const EdgeInsets.all(8), child: Text('Los cambios de planes se aplican al instante a todas las cuentas de ese plan.', style: TextStyle(fontSize: 13, color: p.secondary))),
          ];
        },
      );
}

class AdminAudit extends StatefulWidget {
  const AdminAudit({super.key});
  @override
  State<AdminAudit> createState() => _AdminAuditState();
}

class _AdminAuditState extends State<AdminAudit> {
  String _q = '';
  late Future<Map<String, dynamic>?> _f = Api.adminAudit();
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _f,
        builder: (c, snap) {
          final d = snap.data;
          final items = d == null ? const [] : (d['items'] as List);
          return ListView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            TextField(
              decoration: const InputDecoration(hintText: 'Filtrar por acción o cuenta', prefixIcon: Icon(CupertinoIcons.search, size: 20)),
              onSubmitted: (v) => setState(() { _q = v; _f = Api.adminAudit(q: v); }),
            ),
            const SizedBox(height: 10),
            if (d != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [Pill(d['chain_ok'] == true ? 'Cadena íntegra' : 'Cadena alterada', icon: CupertinoIcons.link, color: d['chain_ok'] == true ? AC.green : AC.red)])),
            if (snap.connectionState != ConnectionState.done) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator.adaptive())),
            if (snap.connectionState == ConnectionState.done && d == null) const Card2(child: Text('No se pudo cargar la auditoría.', style: TextStyle(color: AC.red))),
            if (d != null)
              Group(children: [
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${(it as Map)['action']}', style: TextStyle(fontWeight: FontWeight.w700, color: p.label)),
                      Text('${it['actor'] ?? 'sistema'}${it['target'] != null ? ' → ${it['target']}' : ''}', style: TextStyle(fontSize: 13, color: p.secondary)),
                      Text('${it['ts']}'.replaceFirst('T', ' ').split('.').first, style: TextStyle(fontSize: 11.5, color: p.secondary)),
                    ]),
                  ),
              ]),
            if (_q.isNotEmpty && items.isEmpty && d != null) Text('Sin resultados.', style: TextStyle(color: p.secondary)),
          ]);
        },
      ),
    );
  }
}

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Planes y límites')),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: Api.adminPlans(),
          builder: (c, snap) {
            final d = snap.data;
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator.adaptive());
            if (d == null) return const Center(child: Text('No se pudo cargar.', style: TextStyle(color: AC.red)));
            return ListView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              for (final x in (d['items'] as List)) _PlanEditor(code: '${(x as Map)['code']}', limits: Map<String, dynamic>.from(x['limits'] as Map)),
            ]);
          },
        ),
      );
}

const _limitNames = {
  'max_contacts': 'Contactos de emergencia', 'max_devices': 'Pulseras', 'max_photos_per_emergency': 'Fotos por emergencia',
  'allow_audio': 'Permitir audio', 'allow_video': 'Permitir video', 'auto_record': 'Grabación automática',
  'institutional_dispatch': 'Despacho institucional', 'retention_days': 'Días de retención', 'health_history_days': 'Historial de salud (días)',
  'max_places': 'Lugares seguros', 'max_messages_per_day': 'Mensajes por día',
};

class _PlanEditor extends StatefulWidget {
  const _PlanEditor({required this.code, required this.limits});
  final String code;
  final Map<String, dynamic> limits;
  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  late final Map<String, dynamic> _l = Map.of(widget.limits);
  final _ctl = <String, TextEditingController>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final e in _l.entries) {
      if (e.value is num) _ctl[e.key] = TextEditingController(text: '${e.value}');
    }
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final prem = widget.code == 'PREMIUM';
    return Card2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(CupertinoIcons.star_fill, color: prem ? AC.orange : AC.gray, size: 18),
          const SizedBox(width: 8),
          Text(prem ? 'Premium' : 'Normal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.label)),
        ]),
        const SizedBox(height: 8),
        for (final e in _l.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(_limitNames[e.key] ?? e.key, style: TextStyle(color: p.label))),
              if (e.value is bool)
                Switch.adaptive(value: e.value as bool, onChanged: (v) => setState(() => _l[e.key] = v))
              else if (e.value is num)
                SizedBox(
                  width: 84,
                  child: TextField(controller: _ctl[e.key], keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10))),
                ),
            ]),
          ),
        const SizedBox(height: 10),
        AppButton(
          label: 'Guardar plan', icon: CupertinoIcons.check_mark_circled_solid, loading: _busy,
          onPressed: () async {
            for (final e in _ctl.entries) {
              final n = int.tryParse(e.value.text.trim());
              if (n == null || n < 0) { toast(context, 'Valor no válido en "${_limitNames[e.key] ?? e.key}"'); return; }
              _l[e.key] = n;
            }
            setState(() => _busy = true);
            final err = await Api.adminPutLimits(widget.code, _l);
            if (!mounted) return;
            setState(() => _busy = false);
            toast(context, err == null ? 'Plan actualizado' : errText(err));
          },
        ),
      ]),
    );
  }
}


// =====================================================================================================
// AVISOS GLOBALES
// =====================================================================================================
const _levelColor = {'info': AC.blue, 'warning': AC.orange, 'critical': AC.red};
const _levelIcon = {'info': CupertinoIcons.info_circle_fill, 'warning': CupertinoIcons.exclamationmark_triangle_fill, 'critical': CupertinoIcons.exclamationmark_octagon_fill};

class AdminAnnouncements extends StatelessWidget {
  const AdminAnnouncements({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: _Loader(
          title: 'Avisos',
          subtitle: 'Mensajes que ven todos los usuarios',
          load: Api.adminAnnouncements,
          builder: (context, d, reload) {
            final p = Pal.of(context);
            final items = [for (final x in (d['items'] as List)) Map<String, dynamic>.from(x as Map)];
            return [
              AppButton(
                label: 'Nuevo aviso',
                icon: CupertinoIcons.add,
                onPressed: () async {
                  final ok = await showSheet<bool>(context, (_) => const _NewAnnouncement());
                  if (ok == true) reload();
                },
              ),
              const SizedBox(height: 12),
              if (items.isEmpty) Card2(child: Text('No hay avisos publicados.', style: TextStyle(color: p.secondary))),
              for (final a in items)
                Card2(
                  color: (_levelColor[a['level']] ?? AC.blue).withOpacity(a['active'] == true ? 0.12 : 0.04),
                  child: Row(children: [
                    Icon(_levelIcon[a['level']] ?? CupertinoIcons.info_circle_fill, color: _levelColor[a['level']] ?? AC.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${a['title']}', style: TextStyle(fontWeight: FontWeight.w700, color: p.label)),
                        Text('${a['body']}', style: TextStyle(fontSize: 13, color: p.secondary)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, children: [
                          Pill('${a['audience']}', color: AC.purple),
                          Pill(a['active'] == true ? 'Activo' : 'Vencido', color: a['active'] == true ? AC.green : AC.gray),
                        ]),
                      ]),
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.delete_solid, color: AC.red),
                      onPressed: () async {
                        final e = await Api.adminDeleteAnnouncement('${a['id']}');
                        if (context.mounted) toast(context, e == null ? 'Aviso eliminado' : errText(e));
                        reload();
                      },
                    ),
                  ]),
                ),
            ];
          },
        ),
      );
}

class _NewAnnouncement extends StatefulWidget {
  const _NewAnnouncement();
  @override
  State<_NewAnnouncement> createState() => _NewAnnouncementState();
}

class _NewAnnouncementState extends State<_NewAnnouncement> {
  final _t = TextEditingController(), _b = TextEditingController();
  String _level = 'info', _aud = 'ALL';
  int _days = 7;
  bool _busy = false;

  @override
  void dispose() {
    _t.dispose();
    _b.dispose();
    super.dispose();
  }

  Widget _chips(Map<String, String> opts, String cur, void Function(String) set) => Wrap(
        spacing: 8,
        children: [for (final e in opts.entries) ChoiceChip(label: Text(e.value), selected: cur == e.key, onSelected: (_) => setState(() => set(e.key)))],
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nuevo aviso', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: _t, maxLength: 80, decoration: const InputDecoration(labelText: 'Título')),
            TextField(controller: _b, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'Mensaje')),
            const SizedBox(height: 8),
            _chips({'info': 'Info', 'warning': 'Importante', 'critical': 'Crítico'}, _level, (v) => _level = v),
            const SizedBox(height: 8),
            _chips({'ALL': 'Todos', 'NORMAL': 'Normal', 'PREMIUM': 'Premium'}, _aud, (v) => _aud = v),
            const SizedBox(height: 8),
            _chips({'1': '1 día', '7': '7 días', '30': '30 días'}, '$_days', (v) => _days = int.parse(v)),
            const SizedBox(height: 16),
            AppButton(
              label: 'Publicar',
              icon: CupertinoIcons.paperplane_fill,
              loading: _busy,
              onPressed: () async {
                if (_t.text.trim().isEmpty || _b.text.trim().isEmpty) {
                  toast(context, 'Escribe título y mensaje');
                  return;
                }
                setState(() => _busy = true);
                final e = await Api.adminCreateAnnouncement(_t.text, _b.text, _level, _aud, _days);
                if (!mounted) return;
                setState(() => _busy = false);
                if (e == null) {
                  Navigator.pop(context, true);
                } else {
                  toast(context, errText(e));
                }
              },
            ),
          ]),
        ),
      );
}
