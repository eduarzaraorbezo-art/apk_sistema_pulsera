import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'charts.dart';
import 'home_screen.dart' show mmss;
import 'pin_pad.dart';
import 'theme.dart';

/// Capa que cubre toda la app cuando hay una caída, una búsqueda del teléfono o una llamada falsa.
class TakeoverHost extends StatelessWidget {
  const TakeoverHost({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return switch (s.takeover) {
      Takeover.fall => _FallView(s),
      Takeover.deviation => _FallView(s, deviation: true),
      Takeover.findPhone => _FindPhoneView(s),
      Takeover.fakeCall => _FakeCallView(s),
      Takeover.none => const SizedBox.shrink(),
    };
  }
}

class _Full extends StatelessWidget {
  const _Full({required this.colors, required this.child});
  final List<Color> colors;
  final Widget child;
  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: Material(
          child: Container(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors)),
            child: SafeArea(child: Padding(padding: const EdgeInsets.all(28), child: child)),
          ),
        ),
      );
}

class _FallView extends StatelessWidget {
  const _FallView(this.s, {this.deviation = false});
  final AppState s;
  final bool deviation;
  @override
  Widget build(BuildContext context) => _Full(
        colors: const [Color(0xFFB71C1C), Color(0xFF5A0A0A)],
        child: Column(children: [
          const Spacer(),
          const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.white, size: 64),
          const SizedBox(height: 12),
          Text(deviation ? '¿Todo bien?' : '¿Te caíste?', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(deviation ? 'Te alejaste de tu ruta segura. Si no respondes, pediremos ayuda.' : 'Si no respondes, pediremos ayuda automáticamente.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 28),
          CountdownRing(
            progress: s.fallSeconds / 30, color: Colors.white, size: 190,
            child: Text('${s.fallSeconds}', style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF1B5E20), minimumSize: const Size.fromHeight(58)),
            onPressed: () async {
              final r = await askPin(context, title: 'PIN para confirmar');
              if (r != null && await s.afterPin(r)) s.stopTakeover();
            },
            child: const Text('Estoy bien', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: s.fallNeedHelp, child: const Text('Necesito ayuda ahora', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _FindPhoneView extends StatelessWidget {
  const _FindPhoneView(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) => _Full(
        colors: const [Color(0xFF0A84FF), Color(0xFF0B2E73)],
        child: Column(children: [
          const Spacer(),
          const Icon(CupertinoIcons.bell_fill, color: Colors.white, size: 72),
          const SizedBox(height: 14),
          const Text('Tu pulsera te busca', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Este teléfono está sonando y vibrando.', style: TextStyle(color: Colors.white70, fontSize: 16)),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AC.blue, minimumSize: const Size.fromHeight(58)),
            onPressed: s.stopTakeover,
            child: const Text('Detener', style: TextStyle(fontSize: 20)),
          ),
        ]),
      );
}

/// Llamada entrante falsa con aspecto de teléfono: sirve para salir de una situación incómoda.
class _FakeCallView extends StatefulWidget {
  const _FakeCallView(this.s);
  final AppState s;
  @override
  State<_FakeCallView> createState() => _FakeCallViewState();
}

class _FakeCallViewState extends State<_FakeCallView> {
  bool _answered = false;
  int _sec = 0;

  void _answer() {
    widget.s.answerFakeCall(); // deja de sonar; la pantalla de llamada sigue
    setState(() => _answered = true);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _sec++);
      return widget.s.takeover == Takeover.fakeCall;
    });
  }

  @override
  Widget build(BuildContext context) => _Full(
        colors: const [Color(0xFF2C2C2E), Color(0xFF000000)],
        child: Column(children: [
          const SizedBox(height: 40),
          CircleAvatar(radius: 48, backgroundColor: Colors.white24, child: Text(widget.s.fakeCallName[0], style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w600))),
          const SizedBox(height: 18),
          Text(widget.s.fakeCallName, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(_answered ? mmss(_sec) : 'móvil', style: const TextStyle(color: Colors.white70, fontSize: 18)),
          const Spacer(),
          if (!_answered)
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _Round(color: AC.red, icon: CupertinoIcons.phone_down_fill, label: 'Rechazar', onTap: widget.s.stopTakeover),
              _Round(color: AC.green, icon: CupertinoIcons.phone_fill, label: 'Aceptar', onTap: _answer),
            ])
          else
            _Round(color: AC.red, icon: CupertinoIcons.phone_down_fill, label: 'Colgar', onTap: widget.s.stopTakeover),
          const SizedBox(height: 30),
        ]),
      );
}

class _Round extends StatelessWidget {
  const _Round({required this.color, required this.icon, required this.label, required this.onTap});
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(width: 74, height: 74, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 32)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ]),
      );
}
