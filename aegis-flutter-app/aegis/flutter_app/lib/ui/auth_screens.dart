import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
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
            const SizedBox(height: 10),
            Text('¿Sin cuenta? Tu cuenta la crea el administrador de AEGIS.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Pal.of(context).secondary)),
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
