import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';

/// Contenedor de página: título grande estilo iOS + lista con espacio para la barra inferior.
class Page2 extends StatelessWidget {
  const Page2({super.key, required this.title, this.subtitle, this.trailing, required this.children});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: p.label, letterSpacing: -0.5)),
                if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 15, color: p.secondary)),
              ]),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// Tarjeta redondeada.
class Card2 extends StatelessWidget {
  const Card2({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.margin = const EdgeInsets.only(bottom: 12)});
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? p.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null ? null : () { HapticFeedback.selectionClick(); onTap!(); },
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Pal.of(context).secondary, letterSpacing: 0.4))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Icono cuadrado de color (como en Ajustes de iOS).
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, this.color, {super.key, this.size = 32});
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.28)),
        child: Icon(icon, color: Colors.white, size: size * 0.6),
      );
}

/// Lista agrupada con separadores.
class Group extends StatelessWidget {
  const Group({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) items.add(Divider(height: 1, thickness: 0.5, indent: 58, color: p.separator));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }
}

class Row2 extends StatelessWidget {
  const Row2({super.key, required this.icon, required this.color, required this.title, this.value, this.subtitle, this.trailing, this.onTap, this.chevron = false});
  final IconData icon;
  final Color color;
  final String title;
  final String? value, subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return InkWell(
      onTap: onTap == null ? null : () { HapticFeedback.selectionClick(); onTap!(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          IconBadge(icon, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 17, color: p.label)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: p.secondary)),
            ]),
          ),
          if (value != null) Flexible(child: Text(value!, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, color: p.secondary))),
          if (trailing != null) trailing!,
          if (chevron) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(CupertinoIcons.chevron_right, size: 15, color: p.secondary)),
        ]),
      ),
    );
  }
}

/// Mosaico de métrica (SpO2, temperatura, pasos…).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.color, required this.label, required this.value, this.unit = ''});
  final IconData icon;
  final Color color;
  final String label, value, unit;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6), Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)))]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.label)),
          const SizedBox(width: 3),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(unit, style: TextStyle(fontSize: 13, color: p.secondary))),
        ]),
      ]),
    );
  }
}

/// Control segmentado estilo iOS.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.items, required this.onChanged});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.fill, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (final e in items.entries)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () { HapticFeedback.selectionClick(); onChanged(e.key); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                    color: e.key == value ? (p.dark ? const Color(0xFF636366) : Colors.white) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Text(e.value, style: TextStyle(fontSize: 13, fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w500, color: p.label)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Botón circular de acción rápida.
class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Column(children: [
          Container(
            width: 58, height: 58,
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 12, color: p.label)),
        ]),
      ),
    );
  }
}

/// Barra inferior translúcida (efecto cristal).
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.index, required this.onTap, required this.items});
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, String)> items;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(color: p.card.withOpacity(0.78), border: Border(top: BorderSide(color: p.separator, width: 0.5))),
          padding: EdgeInsets.only(top: 8, bottom: MediaQuery.of(context).padding.bottom + 6),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { if (i != index) HapticFeedback.selectionClick(); onTap(i); },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(items[i].$1, size: 25, color: i == index ? AC.blue : AC.gray),
                    const SizedBox(height: 2),
                    Text(items[i].$2, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: i == index ? AC.blue : AC.gray)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Hoja inferior redondeada con asa.
Future<T?> showSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  final p = Pal.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 38, height: 5, decoration: BoxDecoration(color: p.separator, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 14),
            builder(c),
          ]),
        ),
      ),
    ),
  );
}

void toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)} ${t(d.hour)}:${t(d.minute)}';
}

/// Traduce los códigos de error del backend a un mensaje para el usuario.
String errText(String? c) {
  switch (c) {
    case 'invalid_credentials': return 'Usuario o contraseña incorrectos.';
    case 'totp_required': return 'Escribe el código de 6 dígitos de tu app de autenticación.';
    case 'invalid_totp': return 'Código MFA incorrecto o vencido.';
    case 'account_suspended': return 'Tu cuenta está suspendida. Contacta al administrador.';
    case 'too_many_attempts': return 'Demasiados intentos. Espera 15 minutos.';
    case 'weak_password': return 'La contraseña debe tener 10+ caracteres, letras y números, y ser distinta de la actual.';
    case 'network': return 'Sin conexión con el servidor. Revisa tu Internet.';
    case 'email_taken': return 'Ese usuario o correo ya existe.';
    case 'invalid_phone': return 'Teléfono no válido (usa 6-15 dígitos, con código de país).';
    case 'image_too_large': return 'La imagen pesa demasiado (máximo 256 KB).';
    case 'forbidden': return 'No tienes permiso para esto.';
    case 'mfa_required': return 'Esta acción requiere verificar MFA.';
    case 'plan_limit_messages': return 'Llegaste al límite diario de mensajes de tu plan.';
    case 'cannot_suspend_superadmin':
    case 'cannot_delete': return 'No se puede hacer eso con esta cuenta.';
    default: return 'No se pudo completar (${c ?? 'error'}). Inténtalo de nuevo.';
  }
}

/// Campo de contraseña con ojo para mostrar/ocultar.
class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, required this.hint, this.onChanged, this.onSubmitted});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hide = true;
  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _hide,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: IconButton(icon: Icon(_hide ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 20), onPressed: () => setState(() => _hide = !_hide)),
        ),
      );
}

/// Foto de perfil o inicial.
class AvatarView extends StatelessWidget {
  const AvatarView({super.key, required this.bytes, required this.initial, this.radius = 28});
  final Uint8List? bytes;
  final String initial;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: AC.blue,
        backgroundImage: bytes == null ? null : MemoryImage(bytes!),
        child: bytes == null ? Text(initial, style: TextStyle(color: Colors.white, fontSize: radius * 0.85, fontWeight: FontWeight.w700)) : null,
      );
}
