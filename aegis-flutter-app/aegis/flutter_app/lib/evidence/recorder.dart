import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../data/db.dart';
import '../sync/sync_service.dart';

/// Grabación de evidencia con el micrófono del teléfono (la pulsera usará el suyo cuando exista el canal MEDIA).
/// Graba en trozos de 30 s: si Android mata la app, lo grabado ya está guardado. Cada trozo se sube en cuanto hay red.
/// Solo Premium puede usarla: lo decide la pantalla/estado y lo hace cumplir el servidor.
class EvidenceRecorder extends ChangeNotifier {
  final _rec = AudioRecorder();
  final _uuid = const Uuid();
  static const chunkSeconds = 30;

  bool active = false;
  bool auto = false;
  bool silent = false; // sin indicador en pantalla (SOS silencioso)
  String? session, trigger, error;
  int seconds = 0, saved = 0;
  Timer? _chunk, _clock;
  int _chunkStartMs = 0;
  bool _flushing = false;
  bool planBlocked = false; // el servidor dijo que el plan no lo permite

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/evidence');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// [emergencyId]: si se graba por un SOS, la evidencia cuelga de esa emergencia; si no, se crea una sesión nueva.
  Future<bool> start({String? emergencyId, required String trigger, bool auto = false, bool silent = false}) async {
    if (active) return true;
    error = null;
    try {
      if (!await _rec.hasPermission()) {
        error = 'Falta el permiso del micrófono.';
        notifyListeners();
        return false;
      }
      session = emergencyId ?? _uuid.v4();
      this.trigger = trigger;
      this.auto = auto;
      this.silent = silent;
      seconds = 0;
      saved = 0;
      active = true;
      await _begin();
      _chunk = Timer.periodic(const Duration(seconds: chunkSeconds), (_) => _rotate());
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        seconds++;
        notifyListeners();
      });
      notifyListeners();
      return true;
    } catch (e) {
      active = false;
      error = 'No se pudo iniciar la grabación.';
      notifyListeners();
      return false;
    }
  }

  Future<void> _begin() async {
    final path = '${(await _dir()).path}/${_uuid.v4()}.m4a';
    _chunkStartMs = DateTime.now().millisecondsSinceEpoch;
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000, numChannels: 1), path: path);
  }

  Future<void> _end() async {
    final path = await _rec.stop();
    if (path == null) return;
    final dur = ((DateTime.now().millisecondsSinceEpoch - _chunkStartMs) / 1000).round();
    if (dur < 1 || !await File(path).exists()) return;
    await AegisDb.addEvidence({
      'client_id': _uuid.v4(), 'session': session, 'path': path, 'kind': 'audio', 'mime': 'audio/mp4',
      'trigger_': trigger, 'auto': auto ? 1 : 0, 'duration': dur, 'created': DateTime.now().millisecondsSinceEpoch,
    });
    saved++;
  }

  Future<void> _rotate() async {
    if (!active) return;
    try {
      await _end();
      await _begin();
    } catch (_) {
      error = 'Se interrumpió la grabación.';
      await stop();
      return;
    }
    flush();
    notifyListeners();
  }

  Future<void> stop() async {
    if (!active) return;
    _chunk?.cancel();
    _clock?.cancel();
    active = false;
    try {
      await _end();
    } catch (_) {}
    notifyListeners();
    flush();
  }

  /// Sube lo pendiente. Se llama tras cada trozo, al volver la red y en la sincronización periódica.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      for (final r in await AegisDb.pendingEvidence()) {
        final cid = r['client_id'] as String;
        final f = File(r['path'] as String);
        if (!await f.exists()) {
          await AegisDb.removeEvidence(cid);
          continue;
        }
        final bytes = await f.readAsBytes();
        final code = await Api.uploadEvidence(r['session'] as String, cid, r['kind'] as String, r['mime'] as String, bytes,
            sha256.convert(bytes).toString(), trigger: (r['trigger_'] as String?) ?? 'manual', auto: (r['auto'] as int?) == 1, durationS: r['duration'] as int?);
        if (code == null) break; // sin red: se reintenta luego
        if (code == 201 || code == 200) {
          await f.delete();
          await AegisDb.removeEvidence(cid);
        } else if (code == 403) {
          planBlocked = true; // plan Normal: no se puede guardar esto en el servidor
          await f.delete();
          await AegisDb.removeEvidence(cid);
          notifyListeners();
        } else if (code >= 400 && code < 500 && code != 401 && code != 429) {
          await f.delete(); // el servidor lo rechazó de forma definitiva
          await AegisDb.removeEvidence(cid);
        } else {
          await AegisDb.bumpEvidence(cid);
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> reset() async {
    await stop();
    for (final r in await AegisDb.pendingEvidence()) {
      try { await File(r['path'] as String).delete(); } catch (_) {}
    }
  }

  @override
  void dispose() {
    _chunk?.cancel();
    _clock?.cancel();
    _rec.dispose();
    super.dispose();
  }
}
