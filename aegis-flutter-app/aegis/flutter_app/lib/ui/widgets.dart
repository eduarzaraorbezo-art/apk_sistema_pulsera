import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';

/// Liquid Glass: desenfoque + saturación del fondo (efecto de refracción), tinte adaptable al modo claro/oscuro,
/// borde con luz y un brillo especular en la parte superior.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 20, this.borderRadius, this.blur = 0, this.tint, this.strong = false, this.padding});
  final Widget child;
  final double radius, blur;
  final BorderRadius? borderRadius;
  final Color? tint;
  final bool strong;
  final EdgeInsets? padding;

  static ImageFilter _filter(double blur) {
    const s = 1.7, lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final m = <double>[
      lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0,
      lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
      lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    return ImageFilter.compose(outer: ColorFilter.matrix(m), inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.mirror));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final r = borderRadius ?? BorderRadius.circular(radius);
    final base = tint ?? (strong ? p.glassStrong : p.glass);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [base, base.withOpacity(base.opacity * 0.72)]),
        border: Border.all(color: p.glassEdge, width: 0.8),
      ),
      child: Stack(fit: StackFit.passthrough, children: [
        padding == null ? child : Padding(padding: padding!, child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0, 0.4],
                  colors: [Colors.white.withOpacity(p.dark ? 0.08 : 0.30), Colors.white.withOpacity(0)],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
    // El desenfoque en tiempo real es caro: solo se usa en barra, hojas y paneles (blur > 0).
    if (blur <= 0) return body;
    return ClipRRect(borderRadius: r, child: BackdropFilter(filter: _filter(blur), child: body));
  }
}

/// Efecto de pulsación: se encoge suavemente al tocar (como iOS).
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onTap, this.scale = 0.95});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () { HapticFeedback.selectionClick(); widget.onTap!(); },
      child: AnimatedScale(scale: _down ? widget.scale : 1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut, child: widget.child),
    );
  }
}

/// Aparición escalonada (fade + desplazamiento) para listas.
class Appear extends StatelessWidget {
  const Appear({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 320 + 70 * index.clamp(0, 8).toInt()),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 22 * (1 - v)), child: c)),
        child: child,
      );
}

/// Botón principal en forma de pastilla con degradado, brillo y animación de pulsación.
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, required this.onPressed, this.icon, this.color = AC.blue, this.loading = false, this.compact = false, this.outline = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool loading, compact, outline;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final off = onPressed == null || loading;
    final fg = outline ? color : Colors.white;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: PressScale(
        onTap: off ? null : onPressed,
        child: Container(
          height: compact ? 40 : 54,
          padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: outline ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, 0.18)!, color]),
            color: outline ? color.withOpacity(0.10) : null,
            border: Border.all(color: outline ? color.withOpacity(0.5) : Colors.white.withOpacity(0.35), width: 1),
            boxShadow: outline ? null : [BoxShadow(color: color.withOpacity(p.dark ? 0.35 : 0.30), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (loading)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
            else if (icon != null)
              Icon(icon, size: compact ? 17 : 20, color: fg),
            if (loading || icon != null) const SizedBox(width: 8),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 14 : 17, fontWeight: FontWeight.w700, color: fg))),
          ]),
        ),
      ),
    );
  }
}

/// Etiqueta redonda (estado, plan, filtros).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.color = AC.blue, this.filled = false});
  final String text;
  final IconData? icon;
  final Color color;
  final bool filled;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(filled ? 0 : 0.35), width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: filled ? Colors.white : color), const SizedBox(width: 5)],
          Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: filled ? Colors.white : color)),
        ]),
      );
}

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
          for (var i = 0; i < children.length; i++) Appear(index: i, child: children[i]),
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
      child: PressScale(
        onTap: onTap,
        scale: 0.97,
        child: Glass(tint: color, padding: padding, child: child),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(radius: 18, child: Material(type: MaterialType.transparency, child: Column(children: items))),
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
    return Glass(
      padding: const EdgeInsets.all(14),
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
      child: PressScale(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 62, height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, 0.22)!, color]),
              border: Border.all(color: Colors.white.withOpacity(0.35), width: 0.8),
              boxShadow: [BoxShadow(color: color.withOpacity(p.dark ? 0.35 : 0.28), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: Icon(icon, color: Colors.white, size: 27),
          ),
          const SizedBox(height: 7),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.label)),
        ]),
      ),
    );
  }
}

/// Barra inferior flotante de cristal; la pestaña activa se marca con una cápsula de vidrio.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.index, required this.onTap, required this.items});
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, String)> items;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, MediaQuery.of(context).padding.bottom + 10),
      child: Glass(
        radius: 32, blur: 30, strong: true,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { if (i != index) HapticFeedback.selectionClick(); onTap(i); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: i == index ? AC.blue.withOpacity(p.dark ? 0.30 : 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: i == index ? p.glassEdge : Colors.transparent, width: 0.8),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(items[i].$1, size: 24, color: i == index ? AC.blue : p.secondary),
                    const SizedBox(height: 2),
                    Text(items[i].$2, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: i == index ? AC.blue : p.secondary)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Hoja inferior redondeada con asa.
Future<T?> showSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    elevation: 0,
    builder: (c) {
      final p = Pal.of(c);
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(c).viewInsets.bottom + 8),
        child: Glass(
          borderRadius: const BorderRadius.all(Radius.circular(32)), blur: 34, strong: true,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Container(width: 38, height: 5, decoration: BoxDecoration(color: p.secondary.withOpacity(0.5), borderRadius: BorderRadius.circular(3)))),
                const SizedBox(height: 14),
                builder(c),
              ]),
            ),
          ),
        ),
      );
    },
  );
}

void toast(BuildContext c, String msg) {
  final p = Pal.of(c);
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
    content: Glass(radius: 18, blur: 18, strong: true, padding: const EdgeInsets.all(14), child: Text(msg, style: TextStyle(color: p.label, fontWeight: FontWeight.w600))),
  ));
}

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
