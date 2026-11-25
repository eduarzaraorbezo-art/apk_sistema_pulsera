import 'dart:async';
import 'package:flutter/foundation.dart';
import '../sync/sync_service.dart';
import '../track/track_state.dart';

/// "Me siguen": enlace público temporal con mi ubicación. Se actualiza cada 15 s; si no hay red, sigue intentando.
class LiveShare extends ChangeNotifier {
  LiveShare(this.trk);
  final TrackState trk;
  bool active = false;
  String? url;
  DateTime? expires;
  Timer? _t;

  Future<String?> start({int minutes = 120}) async {
    if (!await trk.follow('live')) return null;
    final r = await Api.liveStart(minutes);
    if (r == null) {
      await trk.unfollow('live');
      return null;
    }
    _apply(r);
    _push();
    return url;
  }

  void _apply(Map<String, dynamic> r) {
    active = true;
    url = r['url'] as String?;
    expires = DateTime.tryParse('${r['expires_at']}')?.toLocal();
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 15), (_) => _push());
    notifyListeners();
  }

  Future<void> _push() async {
    if (!active) return;
    if (expires != null && DateTime.now().isAfter(expires!)) {
      await _end();
      return;
    }
    final p = trk.last ?? await trk.position();
    if (p == null) return;
    await Api.livePosition(p.latitude, p.longitude);
  }

  Future<void> _end() async {
    _t?.cancel();
    active = false;
    url = null;
    await trk.unfollow('live');
    notifyListeners();
  }

  Future<void> stop() async {
    if (!active) return;
    await Api.liveStop();
    await _end();
  }

  /// Al abrir la app: si el servidor dice que sigue activo, se retoma.
  Future<void> restore() async {
    final r = await Api.liveStatus();
    if (r == null || r['active'] != true) return;
    if (await trk.follow('live')) _apply(r);
  }

  Future<void> reset() async {
    _t?.cancel();
    active = false;
    url = null;
    await trk.unfollow('live');
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}
