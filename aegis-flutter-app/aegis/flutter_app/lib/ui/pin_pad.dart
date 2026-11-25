import 'package:flutter/material.dart';
import '../safety/pin_store.dart';
import 'theme.dart';

/// Teclado de PIN. Devuelve null si se cancela. El PIN de coacción devuelve PinResult.duress
/// SIN ningún aviso visible: la pantalla se comporta igual que con el PIN normal.
Future<PinResult?> askPin(BuildContext context, {String title = 'Escribe tu PIN'}) async {
  if (!await PinStore.has()) return PinResult.ok;
  if (!context.mounted) return null;
  return showDialog<PinResult>(context: context, barrierDismissible: true, builder: (_) => _PinDialog(title: title));
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title});
  final String title;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _v = '';
  bool _bad = false;

  Future<void> _tap(String d) async {
    if (_v.length >= 6) return;
    setState(() { _v += d; _bad = false; });
    if (_v.length >= 4) {
      final r = await PinStore.check(_v);
      if (r == PinResult.wrong) {
        if (_v.length == 6) setState(() { _bad = true; _v = ''; });
        return; // con 4-5 dígitos puede que aún esté escribiendo
      }
      if (mounted) Navigator.pop(context, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AlertDialog(
      backgroundColor: p.dark ? const Color(0xE61C1C2E) : const Color(0xE6FFFFFF),
      title: Text(widget.title, textAlign: TextAlign.center),
      content: SizedBox(
        width: 280,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 6; i++)
              Container(margin: const EdgeInsets.all(5), width: 13, height: 13, decoration: BoxDecoration(shape: BoxShape.circle, color: i < _v.length ? AC.blue : p.fill)),
          ]),
          SizedBox(height: 18, child: _bad ? const Text('PIN incorrecto', style: TextStyle(color: AC.red, fontSize: 13)) : null),
          const SizedBox(height: 6),
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '<']])
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final k in row)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    width: 70, height: 52,
                    child: k.isEmpty
                        ? null
                        : TextButton(
                            style: TextButton.styleFrom(backgroundColor: p.fill, shape: const CircleBorder(), foregroundColor: p.label),
                            onPressed: () => k == '<' ? setState(() { if (_v.isNotEmpty) _v = _v.substring(0, _v.length - 1); }) : _tap(k),
                            child: Text(k == '<' ? '⌫' : k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                          ),
                  ),
                ),
            ]),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
