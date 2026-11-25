import 'dart:math';
import 'package:flutter/foundation.dart';
import '../track/track_state.dart';

enum RouteStatus { idle, ok, off, arrived }

/// Distancia (m) de un punto a un segmento, con proyección local plana: suficiente para trayectos de ciudad.
double distToSegmentM(double lat, double lon, List<double> a, List<double> b) {
  final k = cos(lat * pi / 180) * 111320, m = 111320.0;
  double x(double lo) => (lo - lon) * k;
  double y(double la) => (la - lat) * m;
  final ax = x(a[1]), ay = y(a[0]), bx = x(b[1]), by = y(b[0]);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : ((-ax) * dx + (-ay) * dy) / len2;
  final c = t.clamp(0.0, 1.0).toDouble();
  final px = ax + c * dx, py = ay + c * dy;
  return sqrt(px * px + py * py);
}

/// Ruta segura: si te alejas más de [corridorM] de la ruta durante [graceSeconds], avisa (el estado decide qué hacer).
/// La ruta es una línea recta al destino o un recorrido grabado antes. Funciona sin internet (solo GPS).
class SafeRoute extends ChangeNotifier {
  SafeRoute(this.trk);
  final TrackState trk;
  static const arriveM = 60.0, graceSeconds = 45, cooldownSeconds = 300;

  RouteStatus status = RouteStatus.idle;
  String destName = '';
  List<List<double>> line = [];
  double corridorM = 300, offsetM = 0, remainingM = 0;
  int _offSince = 0, _cooldownUntil = 0;

  void Function()? onDeviation;
  void Function()? onArrived;

  bool get active => status != RouteStatus.idle;

  Future<bool> start({required String name, required List<List<double>> polyline, double corridor = 300}) async {
    if (polyline.length < 2) return false;
    if (!await trk.follow('route')) return false;
    destName = name;
    line = polyline;
    corridorM = corridor;
    status = RouteStatus.ok;
    _offSince = 0;
    _cooldownUntil = 0;
    trk.addListener(_check);
    notifyListeners();
    _check();
    return true;
  }

  /// Ruta recta desde donde estoy hasta [dest].
  Future<bool> startStraight({required String name, required double lat, required double lon, double corridor = 300}) async {
    final p = await trk.position();
    if (p == null) return false;
    return start(name: name, polyline: [[p.latitude, p.longitude], [lat, lon]], corridor: corridor);
  }

  void _check() {
    final p = trk.last;
    if (p == null || !active) return;
    var best = double.infinity;
    for (var i = 0; i < line.length - 1; i++) {
      best = min(best, distToSegmentM(p.latitude, p.longitude, line[i], line[i + 1]));
    }
    offsetM = best;
    remainingM = haversineM(p.latitude, p.longitude, line.last[0], line.last[1]);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (remainingM <= arriveM) {
      status = RouteStatus.arrived;
      stop(keepStatus: true);
      onArrived?.call();
      return;
    }
    if (offsetM > corridorM) {
      status = RouteStatus.off;
      if (_offSince == 0) _offSince = now;
      if (now - _offSince >= graceSeconds * 1000 && now > _cooldownUntil) {
        _cooldownUntil = now + cooldownSeconds * 1000;
        onDeviation?.call();
      }
    } else {
      status = RouteStatus.ok;
      _offSince = 0;
    }
    notifyListeners();
  }

  void stop({bool keepStatus = false}) {
    trk.removeListener(_check);
    trk.unfollow('route');
    if (!keepStatus) status = RouteStatus.idle;
    notifyListeners();
  }

  void reset() {
    stop();
    line = [];
  }
}
