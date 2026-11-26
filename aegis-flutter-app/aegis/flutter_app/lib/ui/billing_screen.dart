import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../sync/sync_service.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pasarela de Premium: Yape, Plin, transferencia o tarjeta (en la página segura de la pasarela).
/// AEGIS nunca ve ni guarda datos de tarjeta; el pago se valida por un administrador.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic>? _plans;
  List<Map<String, dynamic>> _pays = const [];
  bool _loading = true, _busy = false;
  String? _method;
  int _months = 1;
  final _ref = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final a = await Api.billingPlans();
    final b = await Api.myPayments();
    if (!mounted) return;
    setState(() {
      _plans = a;
      _pays = [for (final x in ((b?['items'] as List?) ?? const [])) Map<String, dynamic>.from(x as Map)];
      _loading = false;
    });
  }

  String _price(int cents) => 'S/ ${(cents / 100).toStringAsFixed(2)}';

  Future<void> _submit() async {
    if (_method == null) {
      toast(context, 'Elige un medio de pago');
      return;
    }
    if (_ref.text.trim().length < 3) {
      toast(context, 'Escribe el código de operación o referencia del pago');
      return;
    }
    setState(() => _busy = true);
    final e = await Api.declarePayment(_method!, _ref.text.trim(), _months);
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context, e == null ? 'Pago enviado. Lo validaremos en breve.' : errText(e));
    if (e == null) {
      _ref.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = context.watch<AppState>();
    final price = (_plans?['premium_price_cents'] as num?)?.toInt() ?? 0;
    final methods = [for (final m in ((_plans?['methods'] as List?) ?? const [])) Map<String, dynamic>.from(m as Map)];
    final pending = _pays.any((x) => x['status'] == 'PENDING');
    final trialDays = (_plans?['trial_days'] as num?)?.toInt() ?? 7;
    final until = _plans?['premium_until'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('Pasar a Premium')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF2563EB)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('AEGIS Premium', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${_price(price)} al mes', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    for (final t in const ['Audio y video automáticos en una emergencia', 'Evidencias en la nube (150 MB)', 'Informes semanales y alertas silenciosas'])
                      Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 16), const SizedBox(width: 8), Expanded(child: Text(t, style: const TextStyle(color: Colors.white)))])),
                    if (s.isPremium && until != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Tu Premium está activo hasta ${until.substring(0, 10)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                  ]),
                ),
                const SizedBox(height: 14),
                if (!s.isPremium && _plans?['trial_used'] != true)
                  RoundRow([
                    RoundBtn(
                      icon: CupertinoIcons.gift_fill, label: 'Probar $trialDays días gratis', color: AC.green, size: 72,
                      onTap: () async {
                        final e = await Api.startTrial();
                        if (!context.mounted) return;
                        toast(context, e == null ? 'Prueba activada' : errText(e));
                        if (e == null) {
                          await s.reloadAccount();
                          _load();
                        }
                      },
                    ),
                  ]),
                if (pending)
                  Card2(color: AC.orange.withOpacity(0.15), child: Row(children: [
                    const Icon(CupertinoIcons.clock_fill, color: AC.orange),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Tienes un pago en revisión. Se activa apenas lo validemos (hasta 24 h).', style: TextStyle(color: p.label))),
                  ])),
                const SectionLabel('Medio de pago'),
                if (methods.isEmpty) Card2(child: Text('Todavía no hay medios de pago configurados. Pide Premium a tu administrador.', style: TextStyle(color: p.secondary))),
                for (final m in methods)
                  Card2(
                    color: _method == m['id'] ? AC.blue.withOpacity(0.14) : null,
                    onTap: () => setState(() => _method = '${m['id']}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconBadge(_icon('${m['id']}'), _color('${m['id']}'), size: 40),
                        const SizedBox(width: 12),
                        Expanded(child: Text('${m['name']}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.label))),
                        Icon(_method == m['id'] ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle, color: _method == m['id'] ? AC.blue : p.secondary),
                      ]),
                      if (_method == m['id']) ...[
                        const SizedBox(height: 10),
                        if (m['id'] == 'card') ...[
                          Text('Pagarás en la página segura de la pasarela. AEGIS no ve ni guarda los datos de tu tarjeta.', style: TextStyle(color: p.secondary, fontSize: 13)),
                          const SizedBox(height: 10),
                          RoundRow([RoundBtn(icon: CupertinoIcons.creditcard_fill, label: 'Ir a pagar', color: AC.blue, onTap: () => launchUrl(Uri.parse('${m['url']}'), mode: LaunchMode.externalApplication))]),
                          Text('Cuando termines, escribe abajo el número de operación que te muestre.', style: TextStyle(color: p.secondary, fontSize: 13)),
                        ] else ...[
                          Text('Envía ${_price(price * _months)} a:', style: TextStyle(color: p.secondary, fontSize: 13)),
                          Row(children: [
                            Expanded(child: Text('${m['to']}${(m['holder'] ?? '').toString().isEmpty ? '' : '\n${m['holder']}'}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.label))),
                            IconButton(icon: const Icon(CupertinoIcons.doc_on_doc_fill), onPressed: () { Clipboard.setData(ClipboardData(text: '${m['to']}')); toast(context, 'Copiado'); }),
                          ]),
                          Text('Luego escribe abajo el código de operación del comprobante.', style: TextStyle(color: p.secondary, fontSize: 13)),
                        ],
                      ],
                    ]),
                  ),
                const SectionLabel('Duración'),
                Segmented<int>(value: _months, items: const {1: '1 mes', 3: '3 meses', 6: '6 meses', 12: '12 meses'}, onChanged: (v) => setState(() => _months = v)),
                const SizedBox(height: 14),
                TextField(controller: _ref, maxLength: 60, decoration: const InputDecoration(labelText: 'Código de operación / referencia')),
                const SizedBox(height: 6),
                AppButton(label: 'Ya pagué ${_price(price * _months)}', icon: CupertinoIcons.check_mark, loading: _busy, onPressed: (pending || methods.isEmpty) ? null : _submit),
                if (_pays.isNotEmpty) ...[
                  const SectionLabel('Mis pagos'),
                  Group(children: [
                    for (final x in _pays)
                      Row2(
                        icon: x['status'] == 'APPROVED' ? CupertinoIcons.check_mark_circled_solid : (x['status'] == 'REJECTED' ? CupertinoIcons.xmark_circle_fill : CupertinoIcons.clock_fill),
                        color: x['status'] == 'APPROVED' ? AC.green : (x['status'] == 'REJECTED' ? AC.red : AC.orange),
                        title: '${_price((x['amount_cents'] as num).toInt())} · ${x['method']}',
                        subtitle: '${x['months']} mes(es) · ${x['reference']} · ${switch (x['status']) { 'APPROVED' => 'Aprobado', 'REJECTED' => 'Rechazado', _ => 'En revisión' }}',
                      ),
                  ]),
                ],
              ]),
            ),
    );
  }

  IconData _icon(String id) => switch (id) { 'card' => CupertinoIcons.creditcard_fill, 'transfer' => CupertinoIcons.building_2_fill, _ => CupertinoIcons.device_phone_portrait };
  Color _color(String id) => switch (id) { 'yape' => const Color(0xFF7B1FA2), 'plin' => const Color(0xFF00BCD4), 'card' => AC.blue, _ => AC.green };
}
