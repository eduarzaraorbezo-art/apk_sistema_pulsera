import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../data/db.dart';
import '../sos/sos_handler.dart' show notify;
import '../sync/sync_service.dart';

double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final a = pow(sin(rad(lat2 - lat1) / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(rad(lon2 - lon1) / 2), 2);
  return 2 * r * asin(sqrt(a));
}

/// Metadatos de los tipos de lugar de la comunidad: (nombre, color ARGB, nombre de icono Cupertino).
const placeKinds = <String, (String, int, String)>{
  'safe': ('Zona segura', 0xFF30D158, 'shield'),
  'unsafe': ('Zona peligrosa', 0xFFFF453A, 'warning'),
  'police': ('Policía / serenazgo', 0xFF0A84FF, 'police'),
  'hospital': ('Hospital / posta', 0xFFFF375F, 'hospital'),
  'pharmacy': ('Farmacia', 0xFF40C8E0, 'pharmacy'),
  'lit': ('Bien iluminado', 0xFFFFD60A, 'lit'),
  'dark': ('Oscuro / solitario', 0xFF8E8E93, 'dark'),
  'crowded': ('Concurrido', 0xFFFF9F0A, 'crowded'),
  'shelter': ('Refugio / ayuda', 0xFFBF5AF2, 'shelter'),
  'other': ('Otro', 0xFF8E8E93, 'other'),
};

/// Recorrido por GPS. El GPS no necesita internet: los puntos se guardan en el teléfono y se suben cuando hay red.
class TrackState extends ChangeNotifier {
  final _uuid = const Uuid();
  bool active = false;
  String? error;
  String? id;
  int startedMs = 0;
  double distance = 0;
  final List<List<double>> points = []; // [lat, lon, ts_ms]
  Position? last; // última posición conocida (también fuera de un recorrido)
  StreamSubscription<Position>? _sub;
  Timer? _clock;
  int _sinceSave = 0;

  static const stepM = 0.75; // longitud media de paso: es una estimación

  int get steps => (distance / stepM).round();
  int get elapsedSec => active ? ((DateTime.now().millisecondsSinceEpoch - startedMs) / 1000).floor() : 0;
  double get paceMinPerKm => distance < 50 ? 0 : (elapsedSec / 60) / (distance / 1000);

  /// Cierra un recorrido que quedó abierto porque Android mató la app.
  Future<void> recoverInterrupted() async {
    final rows = await AegisDb.tracks();
    for (final r in rows) {
      if (r['ended'] == null || r['ended'] == 0) {
        final pts = (jsonDecode(r['points'] as String) as List);
        final end = pts.isEmpty ? (r['started'] as int) : ((pts.last as List)[2] as num).toInt();
        final row = {...r, 'ended': end};
        await AegisDb.saveTrack(row);
        await _queue(row);
      }
    }
  }

  Future<bool> start() async {
    if (active) return true;
    error = null;
    if (!await Geolocator.isLocationServiceEnabled()) {
      error = 'Activa el GPS del teléfono.';
      notifyListeners();
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      error = 'Falta el permiso de ubicación.';
      notifyListeners();
      return false;
    }
    id = _uuid.v4();
    startedMs = DateTime.now().millisecondsSinceEpoch;
    distance = 0;
    points.clear();
    active = true;
    _sinceSave = 0;
    _openStream();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    await _persist(ended: false);
    notifyListeners();
    return true;
  }

  /// Abre el GPS una sola vez. Lo usan el recorrido, la ubicación en vivo y la ruta segura.
  void _openStream() {
    if (_sub != null) return;
    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 8,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'AEGIS usa tu ubicación',
          notificationText: 'El GPS funciona sin internet.',
          enableWakeLock: true,
        ),
      ),
    ).listen(_onPos, onError: (_) {
      error = 'Se perdió la señal GPS.';
      notifyListeners();
    });
  }

  final Set<String> _followers = {};

  /// Pide mantener el GPS abierto (p. ej. 'live', 'route') aunque no haya recorrido grabándose.
  Future<bool> follow(String who) async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return false;
    _followers.add(who);
    _openStream();
    return true;
  }

  Future<void> unfollow(String who) async {
    _followers.remove(who);
    if (!active && _followers.isEmpty) {
      await _sub?.cancel();
      _sub = null;
    }
  }

  void _onPos(Position p) {
    last = p;
    if (!active) {
      notifyListeners();
      return;
    }
    if (p.accuracy > 60) return; // lecturas muy imprecisas ensucian el recorrido
    final ts = p.timestamp.millisecondsSinceEpoch.toDouble();
    if (points.isNotEmpty) {
      final d = haversineM(points.last[0], points.last[1], p.latitude, p.longitude);
      if (d < 5) return;
      final dt = (ts - points.last[2]) / 1000;
      if (dt > 0 && d / dt > 70) return; // salto imposible (>250 km/h): ruido del GPS
      distance += d;
    }
    points.add([p.latitude, p.longitude, ts]);
    if (++_sinceSave >= 10) {
      _sinceSave = 0;
      _persist(ended: false);
    }
    notifyListeners();
  }

  Map<String, Object?> _row({required bool ended}) => {
        'id': id,
        'started': startedMs,
        'ended': ended ? DateTime.now().millisecondsSinceEpoch : 0,
        'distance': distance,
        'steps': steps,
        'points': jsonEncode(points),
      };

  Future<void> _persist({required bool ended}) => AegisDb.saveTrack(_row(ended: ended));

  Future<void> _queue(Map<String, Object?> r) async {
    final pts = jsonDecode(r['points'] as String);
    if ((pts as List).length < 2) return; // nada que guardar
    await AegisDb.enqueue(_uuid.v4(), 'route', 5, jsonEncode({
      'id': r['id'],
      'started_at': DateTime.fromMillisecondsSinceEpoch(r['started'] as int, isUtc: true).toIso8601String(),
      'ended_at': DateTime.fromMillisecondsSinceEpoch(r['ended'] as int, isUtc: true).toIso8601String(),
      'distance_m': r['distance'],
      'steps': r['steps'],
      'points': pts.length > 6000 ? [for (var i = 0; i < 6000; i++) pts[i * pts.length ~/ 6000]] : pts,
    }));
  }

  Future<void> stop() async {
    if (!active) return;
    _clock?.cancel();
    active = false;
    if (_followers.isEmpty) {
      await _sub?.cancel();
      _sub = null;
    }
    final row = _row(ended: true);
    await AegisDb.saveTrack(row);
    await _queue(row);
    notifyListeners();
  }

  List<List<double>> decodePoints(String json) =>
      [for (final e in jsonDecode(json) as List) [for (final n in e as List) (n as num).toDouble()]];

  Future<List<Map<String, Object?>>> history() => AegisDb.tracks();

  Future<void> remove(String tid) async {
    await AegisDb.deleteTrack(tid);
    await Api.authed('DELETE', '/routes/$tid');
    notifyListeners();
  }

  Future<void> reset() async {
    _followers.clear();
    await _sub?.cancel();
    _sub = null;
    _clock?.cancel();
    active = false;
    points.clear();
    distance = 0;
    last = null;
  }

  /// Posición actual: última conocida del recorrido, o una lectura nueva del GPS.
  Future<Position?> position() async {
    final l = last;
    if (l != null && DateTime.now().difference(l.timestamp).inSeconds < 60) return l;
    try {
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    super.dispose();
  }
}

/// Lugares de la comunidad y alertas SOS cercanas. Los lugares se guardan en caché para verlos sin internet.
class CommunityState extends ChangeNotifier {
  List<Map<String, dynamic>> places = [], alerts = [];
  bool loading = false, offline = false;
  final Set<String> _seen = {};
  Timer? _poll;
  Future<dynamic> Function()? _pos; // devuelve Position?
  bool Function()? _enabled;

  Future<void> loadCache() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString('community_cache');
    if (c != null) places = [for (final e in jsonDecode(c) as List) Map<String, dynamic>.from(e as Map)];
    notifyListeners();
  }

  Future<void> refreshPlaces(double lat, double lon) async {
    loading = true;
    notifyListeners();
    final r = await Api.communityPlaces(lat, lon, radiusKm: 5);
    loading = false;
    offline = r == null;
    if (r != null) {
      places = r;
      (await SharedPreferences.getInstance()).setString('community_cache', jsonEncode(r));
    }
    notifyListeners();
  }

  /// Consulta alertas cercanas cada 30 s mientras el modo ayudante esté activo.
  void startAlertPolling(Future<dynamic> Function() position, bool Function() enabled) {
    _pos = position;
    _enabled = enabled;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => pollAlerts());
    pollAlerts();
  }

  Future<void> pollAlerts() async {
    if (_enabled?.call() != true) {
      if (alerts.isNotEmpty) { alerts = []; notifyListeners(); }
      return;
    }
    final pos = await _pos?.call();
    if (pos == null) return;
    final r = await Api.communityAlerts(pos.latitude as double, pos.longitude as double);
    if (r == null) return;
    for (final a in r) {
      final id = a['id'] as String;
      if (_seen.add(id)) {
        notify(2000 + _seen.length, 'Alguien cerca necesita ayuda', '${a['name']} activó un SOS a ${a['distance_km']} km. Abre AEGIS para ver dónde.', urgent: true);
      }
    }
    alerts = r;
    notifyListeners();
  }

  Future<void> reset() async {
    _poll?.cancel();
    places = [];
    alerts = [];
    _seen.clear();
    (await SharedPreferences.getInstance()).remove('community_cache');
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
