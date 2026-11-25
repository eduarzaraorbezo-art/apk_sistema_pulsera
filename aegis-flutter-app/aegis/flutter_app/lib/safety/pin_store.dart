import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum PinResult { ok, duress, wrong }

/// PIN normal + PIN de coacción. Solo se guardan hashes con sal en el almacenamiento seguro del teléfono; nunca salen de él.
/// Con el PIN normal se cancela una alerta de verdad. Con el de coacción la pantalla parece cancelarse, pero se envía un SOS silencioso.
class PinStore {
  static const _s = FlutterSecureStorage();
  static int _wrong = 0;

  static String _h(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();
  static bool valid(String p) => RegExp(r'^\d{4,6}$').hasMatch(p);

  static Future<bool> has() async => (await _s.read(key: 'pin_ok')) != null;

  /// Devuelve null si salió bien o un código de error.
  static Future<String?> set(String pin, String duress) async {
    if (!valid(pin) || !valid(duress)) return 'invalid_pin';
    if (pin == duress) return 'same_pin';
    final salt = base64Url.encode(List<int>.generate(12, (_) => Random.secure().nextInt(256)));
    await _s.write(key: 'pin_salt', value: salt);
    await _s.write(key: 'pin_ok', value: _h(salt, pin));
    await _s.write(key: 'pin_duress', value: _h(salt, duress));
    return null;
  }

  static Future<PinResult> check(String pin) async {
    final salt = await _s.read(key: 'pin_salt');
    final ok = await _s.read(key: 'pin_ok');
    final du = await _s.read(key: 'pin_duress');
    if (salt == null || ok == null || du == null) return PinResult.ok;
    final h = _h(salt, pin);
    if (h == du) {
      _wrong = 0;
      return PinResult.duress;
    }
    if (h == ok) {
      _wrong = 0;
      return PinResult.ok;
    }
    _wrong++;
    return PinResult.wrong;
  }

  static int get wrongCount => _wrong;

  static Future<void> clear() async {
    for (final k in ['pin_salt', 'pin_ok', 'pin_duress']) {
      await _s.delete(key: k);
    }
    _wrong = 0;
  }
}
