import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../sync/sync_service.dart';
import 'billing_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Fondo degradado de las pantallas de acceso (el mismo violeta/azul del ícono).
class _AuthBg extends StatelessWidget {
  const _AuthBg({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4527A0), Color(0xFF1B1464), Color(0xFF0B0A2E)])),
          child: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child)))),
        ),
      );
}

Widget _logo() => Column(children: [
      ClipRRect(borderRadius: BorderRadius.circular(26), child: Image.asset('assets/logo.png', width: 96, height: 96)),
      const SizedBox(height: 14),
      const Text('AEGIS', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4)),
      const Text('Smart Safety Band', style: TextStyle(color: Colors.white70, fontSize: 15)),
      const SizedBox(height: 28),
    ]);

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Glass(
        radius: 26, strong: true, blur: 30, padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Pantalla inicial: sin sesión no se entra a la app.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController(), _pw = TextEditingController(), _totp = TextEditingController();
  bool _busy = false, _needTotp = false;
  String? _err;

  Future<void> _go() async {
    if (_busy) return;
    if (_user.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _err = 'Escribe tu usuario y tu contraseña.');
      return;
    }
    setState(() { _busy = true; _err = null; });
    final e = await context.read<AppState>().login(_user.text, _pw.text, _totp.text.trim().isEmpty ? null : _totp.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (e == 'totp_required') _needTotp = true;
      _err = e == null ? null : errText(e);
    });
    if (e == null) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) => _AuthBg(
        child: Column(children: [
          _logo(),
          _Panel(children: [
            const Text('Iniciar sesión', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(controller: _user, autocorrect: false, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(hintText: 'Usuario o correo')),
            const SizedBox(height: 10),
            PasswordField(controller: _pw, hint: 'Contraseña', onSubmitted: (_) => _go()),
            if (_needTotp) ...[
              const SizedBox(height: 10),
              TextField(controller: _totp, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(hintText: 'Código MFA de 6 dígitos', counterText: '')),
            ],
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: AC.red, fontSize: 14))),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? 'Entrando…' : 'Entrar')),
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ForgotPasswordScreen())), child: const Text('¿Olvidaste tu contraseña?')),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const RegisterScreen())),
              icon: const Icon(CupertinoIcons.person_add_solid),
              label: const Text('Crear cuenta'),
            ),
          ]),
        ]),
      );
}

/// Cambio de contraseña obligatorio (primer ingreso o tras un restablecimiento).
class ForcedPasswordScreen extends StatelessWidget {
  const ForcedPasswordScreen({super.key});
  @override
  Widget build(BuildContext context) => _AuthBg(
        child: Column(children: [
          _logo(),
          _Panel(children: [
            const Text('Crea tu contraseña', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Por seguridad debes cambiar la contraseña temporal antes de continuar.', style: TextStyle(color: Pal.of(context).secondary)),
            const SizedBox(height: 14),
            const PasswordForm(),
            TextButton(onPressed: context.read<AppState>().signOut, child: const Text('Cerrar sesión')),
          ]),
        ]),
      );
}

/// Formulario de cambio de contraseña con reglas en vivo (se usa también desde Perfil).
class PasswordForm extends StatefulWidget {
  const PasswordForm({super.key, this.onDone});
  final VoidCallback? onDone;
  @override
  State<PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<PasswordForm> {
  final _cur = TextEditingController(), _new = TextEditingController(), _rep = TextEditingController();
  bool _busy = false;
  String? _err;

  bool get _len => _new.text.length >= 10;
  bool get _mix => RegExp(r'[A-Za-z]').hasMatch(_new.text) && RegExp(r'[0-9]').hasMatch(_new.text);
  bool get _diff => _new.text.isNotEmpty && _new.text != _cur.text;
  bool get _same => _new.text.isNotEmpty && _new.text == _rep.text;
  bool get _ok => _len && _mix && _diff && _same && _cur.text.isNotEmpty;

  Widget _rule(bool ok, String t) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Icon(ok ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 16, color: ok ? AC.green : AC.gray),
          const SizedBox(width: 8),
          Text(t, style: TextStyle(fontSize: 13, color: ok ? AC.green : Pal.of(context).secondary)),
        ]),
      );

  Future<void> _save() async {
    setState(() { _busy = true; _err = null; });
    final e = await context.read<AppState>().changePassword(_cur.text, _new.text);
    if (!mounted) return;
    if (e == null) {
      widget.onDone?.call();
    } else {
      setState(() { _busy = false; _err = errText(e); });
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PasswordField(controller: _cur, hint: 'Contraseña actual', onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        PasswordField(controller: _new, hint: 'Nueva contraseña', onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        PasswordField(controller: _rep, hint: 'Repite la nueva contraseña', onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        _rule(_len, 'Al menos 10 caracteres'),
        _rule(_mix, 'Letras y números'),
        _rule(_diff, 'Distinta de la actual'),
        _rule(_same, 'Las dos coinciden'),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: AC.red))),
        const SizedBox(height: 14),
        FilledButton(onPressed: (_ok && !_busy) ? _save : null, child: Text(_busy ? 'Guardando…' : 'Guardar contraseña')),
      ]);
}

/// Activación de MFA (obligatoria para administradores).
class MfaSetupScreen extends StatefulWidget {
  const MfaSetupScreen({super.key});
  @override
  State<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends State<MfaSetupScreen> {
  final _code = TextEditingController();
  String? _err;
  bool _busy = false, _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await context.read<AppState>().startMfa();
      if (mounted && !ok) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    return _AuthBg(
      child: Column(children: [
        _logo(),
        _Panel(children: [
          const Text('Verificación en dos pasos', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Las cuentas de administración necesitan MFA. En Google Authenticator, Authy o similar elige "Ingresar clave de configuración" y escribe esta clave:', style: TextStyle(color: p.secondary)),
          const SizedBox(height: 12),
          if (_failed)
            const Text('No se pudo generar la clave. Revisa tu conexión y vuelve a intentarlo.', style: TextStyle(color: AC.red))
          else if (s.mfaSecret == null)
            const Center(child: CircularProgressIndicator.adaptive())
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.fill, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: SelectableText(s.mfaSecret!, style: const TextStyle(fontFamily: 'monospace', fontSize: 17, letterSpacing: 1.5, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(CupertinoIcons.doc_on_doc), onPressed: () { Clipboard.setData(ClipboardData(text: s.mfaSecret!)); toast(context, 'Clave copiada'); }),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(hintText: 'Código de 6 dígitos', counterText: '')),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: AC.red))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () async {
                setState(() { _busy = true; _err = null; });
                final ok = await s.verifyMfa(_code.text);
                if (mounted && !ok) setState(() { _busy = false; _err = errText('invalid_totp'); });
              },
              child: Text(_busy ? 'Verificando…' : 'Activar y continuar'),
            ),
          ],
          TextButton(onPressed: s.signOut, child: const Text('Cerrar sesión')),
        ]),
      ]),
    );
  }
}


// =====================================================================================================
// RECUPERAR CONTRASEÑA
// =====================================================================================================
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController(), _code = TextEditingController(), _pw = TextEditingController();
  bool _sent = false, _busy = false;
  String? _err;

  Future<void> _send() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _err = 'Escribe tu correo.');
      return;
    }
    setState(() { _busy = true; _err = null; });
    final e = await Api.forgotPassword(_email.text);
    if (!mounted) return;
    setState(() { _busy = false; _err = e == null ? null : errText(e); _sent = e == null; });
  }

  Future<void> _reset() async {
    setState(() { _busy = true; _err = null; });
    final e = await Api.resetPassword(_email.text, _code.text, _pw.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (e == null) {
      toast(context, 'Contraseña cambiada. Ya puedes entrar.');
      Navigator.pop(context);
    } else {
      setState(() => _err = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return _AuthBg(
      child: Column(children: [
        _logo(),
        _Panel(children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.back)),
            const Expanded(child: Text('Recuperar contraseña', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          if (!_sent) ...[
            Text('Escribe el correo de tu cuenta. Te enviaremos un código de 6 dígitos (por correo o SMS al teléfono registrado).', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 12),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(hintText: 'Correo')),
          ] else ...[
            Text('Si la cuenta existe, enviamos un código. Escríbelo y elige tu nueva contraseña (vale 15 minutos).', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 12),
            TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(hintText: 'Código de 6 dígitos', counterText: '')),
            const SizedBox(height: 10),
            PasswordField(controller: _pw, hint: 'Nueva contraseña (10+ con letras y números)'),
          ],
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: AC.red))),
          const SizedBox(height: 14),
          FilledButton(onPressed: _busy ? null : (_sent ? _reset : _send), child: Text(_busy ? 'Un momento…' : (_sent ? 'Cambiar contraseña' : 'Enviar código'))),
          if (_sent) TextButton(onPressed: _busy ? null : _send, child: const Text('Reenviar código')),
          const SizedBox(height: 6),
          Text('¿Eres administrador sin correo (p. ej. "superadmin")? Pide el restablecimiento al responsable del servidor.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.secondary)),
        ]),
      ]),
    );
  }
}

// =====================================================================================================
// REGISTRO: quien compra la pulsera crea su cuenta y elige plan
// =====================================================================================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController(), _phone = TextEditingController(), _pw = TextEditingController(), _pw2 = TextEditingController();
  String _plan = 'NORMAL';
  bool _busy = false;
  String? _err;

  static const _plans = [
    ('NORMAL', 'Normal', 'Gratis', 'SOS, contactos, ubicación, mensajes y comunidad.', CupertinoIcons.person_fill, AC.blue),
    ('TRIAL', 'Prueba Premium', '7 días gratis', 'Prueba todo Premium sin pagar. Luego vuelves a Normal.', CupertinoIcons.gift_fill, AC.green),
    ('PREMIUM', 'Premium', 'Con pago', 'Audio, video y evidencias en la nube, informes y alertas silenciosas.', CupertinoIcons.star_fill, AC.purple),
  ];

  Future<void> _go() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _err = errText('invalid_email'));
      return;
    }
    if (_pw.text != _pw2.text) {
      setState(() => _err = 'Las contraseñas no coinciden.');
      return;
    }
    if (_pw.text.length < 10) {
      setState(() => _err = errText('weak_password'));
      return;
    }
    setState(() { _busy = true; _err = null; });
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    var e = await Api.register(email, _pw.text, _phone.text, _plan);
    if (e == null) e = await s.login(email, _pw.text, null);
    if (!mounted) return;
    setState(() => _busy = false);
    if (e != null) {
      setState(() => _err = errText(e));
      return;
    }
    nav.popUntil((r) => r.isFirst);
    if (_plan == 'PREMIUM') nav.push(MaterialPageRoute<void>(builder: (_) => const PaymentScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return _AuthBg(
      child: Column(children: [
        _logo(),
        _Panel(children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.back)),
            const Expanded(child: Text('Crear cuenta', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(hintText: 'Correo')),
          const SizedBox(height: 10),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Celular con código de país (opcional)')),
          const SizedBox(height: 10),
          PasswordField(controller: _pw, hint: 'Contraseña (10+ con letras y números)'),
          const SizedBox(height: 10),
          PasswordField(controller: _pw2, hint: 'Repite la contraseña'),
          const SizedBox(height: 16),
          Text('Elige tu plan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.label)),
          const SizedBox(height: 8),
          for (final pl in _plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PressScale(
                onTap: () => setState(() => _plan = pl.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: _plan == pl.$1 ? pl.$6.withOpacity(0.18) : p.glass,
                    border: Border.all(color: _plan == pl.$1 ? pl.$6 : p.glassEdge, width: _plan == pl.$1 ? 2 : 1),
                  ),
                  child: Row(children: [
                    IconBadge(pl.$5, pl.$6, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Text(pl.$2, style: TextStyle(fontWeight: FontWeight.w800, color: p.label)), const SizedBox(width: 8), Pill(pl.$3, color: pl.$6)]),
                        const SizedBox(height: 2),
                        Text(pl.$4, style: TextStyle(fontSize: 12.5, color: p.secondary)),
                      ]),
                    ),
                    Icon(_plan == pl.$1 ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle, color: _plan == pl.$1 ? pl.$6 : p.secondary),
                  ]),
                ),
              ),
            ),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_err!, style: const TextStyle(color: AC.red))),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? 'Creando…' : (_plan == 'PREMIUM' ? 'Crear cuenta y pagar' : 'Crear cuenta'))),
        ]),
      ]),
    );
  }
}
