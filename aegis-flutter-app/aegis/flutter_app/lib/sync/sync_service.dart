import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../data/db.dart';

/// Backend en Railway. Para otro servidor: flutter run --dart-define=API_BASE=https://...
const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://backendpulsera-production.up.railway.app');

const _storage = FlutterSecureStorage();
const _json = {'Content-Type': 'application/json'};

/// Resultado de iniciar sesión. [error] es un código del backend o 'network'.
class LoginResult {
  final String? error;
  final String role;
  final bool mustChange, mfaEnabled, mfa;
  const LoginResult({this.error, this.role = '', this.mustChange = false, this.mfaEnabled = false, this.mfa = false});
  bool get ok => error == null;
}

class Api {
  static Map<String, dynamic>? _obj(http.Response? r, [int ok = 200]) =>
      (r != null && r.statusCode == ok && r.body.isNotEmpty) ? jsonDecode(r.body) as Map<String, dynamic> : null;

  /// Código de error del backend (campo "detail") o null.
  static String? errorOf(http.Response? r) {
    if (r == null) return 'network';
    try {
      final d = jsonDecode(r.body);
      if (d is Map && d['detail'] is String) return d['detail'] as String;
    } catch (_) {}
    return 'http_${r.statusCode}';
  }

  static Future<void> _saveSession(Map<String, dynamic> o) async {
    await _storage.write(key: 'access', value: o['access_token'] as String);
    await _storage.write(key: 'refresh', value: o['refresh_token'] as String);
  }

  /// Renueva el access token con el refresh token. true si se renovó.
  static Future<bool> refresh() async {
    final rt = await _storage.read(key: 'refresh');
    if (rt == null) return false;
    try {
      final r = await http.post(Uri.parse('$apiBase/auth/refresh'), headers: _json, body: jsonEncode({'refresh_token': rt}));
      final o = _obj(r);
      if (o == null) return false;
      await _saveSession(o);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// [user] puede ser un correo o un nombre de usuario ("superadmin").
  static Future<LoginResult> login(String user, String password, [String? totp]) async {
    try {
      final r = await http.post(Uri.parse('$apiBase/auth/login'),
          headers: _json, body: jsonEncode({'email': user, 'password': password, if (totp != null) 'totp_code': totp}))
          .timeout(const Duration(seconds: 20));
      final o = _obj(r);
      if (o == null) return LoginResult(error: errorOf(r));
      await _saveSession(o);
      final p = await SharedPreferences.getInstance();
      await p.setString('email', o['email'] as String? ?? user);
      await p.setString('role', o['role'] as String? ?? '');
      return LoginResult(role: o['role'] as String? ?? '', mustChange: o['must_change_password'] == true,
          mfaEnabled: o['mfa_enabled'] == true, mfa: o['mfa'] == true);
    } catch (_) {
      return const LoginResult(error: 'network');
    }
  }

  static Future<void> logout() async {
    await _storage.delete(key: 'access');
    await _storage.delete(key: 'refresh');
    final p = await SharedPreferences.getInstance();
    await p.remove('email');
    await p.remove('role');
  }

  static Future<bool> loggedIn() async => (await _storage.read(key: 'access')) != null;

  /// Petición autenticada con un reintento tras renovar el token. null si no hay sesión o no hay red.
  static Future<http.Response?> authed(String method, String path, [Object? body, Map<String, String>? headers]) async {
    try {
      Future<http.Response> send(String t) {
        final u = Uri.parse('$apiBase$path');
        final h = {..._json, ...?headers, 'Authorization': 'Bearer $t'};
        final b = body == null ? null : (body is List<int> ? body : jsonEncode(body));
        switch (method) {
          case 'POST': return http.post(u, headers: h, body: b);
          case 'PUT': return http.put(u, headers: h, body: b);
          case 'DELETE': return http.delete(u, headers: h);
          default: return http.get(u, headers: h);
        }
      }

      final t = await _storage.read(key: 'access');
      if (t == null) return null;
      var r = await send(t).timeout(const Duration(seconds: 15));
      if (r.statusCode == 401 && await refresh()) {
        r = await send((await _storage.read(key: 'access'))!).timeout(const Duration(seconds: 15));
      }
      return r;
    } catch (_) {
      return null;
    }
  }

  // ---- cuenta ----
  static Future<http.Response?> me() => authed('GET', '/me');

  /// Cambia la contraseña. Devuelve null si salió bien o el código de error (weak_password, invalid_credentials…).
  static Future<String?> changePassword(String current, String next) async {
    final r = await authed('POST', '/auth/change-password', {'current_password': current, 'new_password': next});
    final o = _obj(r);
    if (o == null) return errorOf(r);
    await _saveSession(o);
    return null;
  }

  static Future<Map<String, dynamic>?> mfaSetup() async => _obj(await authed('POST', '/auth/mfa/setup'));

  static Future<bool> mfaVerify(String code) async {
    final o = _obj(await authed('POST', '/auth/mfa/verify', {'code': code}));
    if (o == null) return false;
    await _saveSession(o);
    return true;
  }

  static Future<String?> putPhone(String? phone) async {
    final r = await authed('PUT', '/me/account', {'phone': phone});
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  static Future<String?> putAvatar(List<int> bytes, String mime) async {
    final r = await authed('PUT', '/me/avatar', bytes, {'Content-Type': mime});
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  static Future<List<int>?> getAvatar() async {
    final r = await authed('GET', '/me/avatar');
    return r?.statusCode == 200 ? r!.bodyBytes : null;
  }

  static Future<void> deleteAvatar() => authed('DELETE', '/me/avatar');

  // ---- ajustes y mensajes ----
  static Future<Map<String, dynamic>?> getSettings() async => _obj(await authed('GET', '/me/settings'));

  static Future<String?> putSettings(Map<String, dynamic> s) async {
    final r = await authed('PUT', '/me/settings', s);
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  static Future<String?> pushContacts(List<Map<String, Object?>> contacts) async {
    final r = await authed('PUT', '/contacts/sync', {'contacts': [for (final c in contacts) {'name': c['name'], 'phone': c['phone']}]});
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  /// Envía un mensaje a los contactos desde el servidor. Devuelve (estados, error).
  static Future<(List<Map<String, dynamic>>, String?)> sendMessage(String clientId,
      {String? templateId, String? text, double? lat, double? lon}) async {
    final r = await authed('POST', '/messages/send',
        {'client_id': clientId, if (templateId != null) 'template_id': templateId, if (text != null) 'text': text, if (lat != null) 'lat': lat, if (lon != null) 'lon': lon});
    final o = _obj(r);
    if (o == null) return (<Map<String, dynamic>>[], errorOf(r));
    return ([for (final x in (o['results'] as List)) Map<String, dynamic>.from(x as Map)], null);
  }

  static Future<List<Map<String, dynamic>>> messageHistory() async {
    final r = await authed('GET', '/messages');
    if (r == null || r.statusCode != 200) return [];
    return [for (final x in jsonDecode(r.body) as List) Map<String, dynamic>.from(x as Map)];
  }

  // ---- cuenta: recuperar contraseña y registro (sin sesión) ----
  static Future<String?> _public(String path, Map<String, Object?> body, int ok) async {
    try {
      final r = await http.post(Uri.parse('$apiBase$path'), headers: _json, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
      return r.statusCode == ok ? null : errorOf(r);
    } catch (_) {
      return 'network';
    }
  }

  static Future<String?> forgotPassword(String email) => _public('/auth/forgot', {'email': email.trim()}, 200);
  static Future<String?> resetPassword(String email, String code, String pw) => _public('/auth/reset', {'email': email.trim(), 'code': code.trim(), 'new_password': pw}, 200);
  static Future<String?> register(String email, String pw, String? phone, String plan) =>
      _public('/auth/register', {'email': email.trim(), 'password': pw, 'plan': plan, if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim()}, 201);

  // ---- planes y pagos ----
  static Future<Map<String, dynamic>?> billingPlans() => _getMap('/billing/plans');
  static Future<Map<String, dynamic>?> myPayments() => _getMap('/billing/payments');
  static Future<String?> startTrial() async {
    final r = await authed('POST', '/billing/trial');
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  static Future<String?> declarePayment(String method, String reference, int months) async {
    final r = await authed('POST', '/billing/payments', {'method': method, 'reference': reference, 'months': months});
    return r?.statusCode == 201 ? null : errorOf(r);
  }

  static Future<Map<String, dynamic>?> adminPayments({String? status}) => _getMap('/admin/payments${status == null ? '' : '?status=$status'}');
  static Future<String?> adminReviewPayment(String id, bool approve) async {
    final r = await authed('POST', '/admin/payments/$id/${approve ? 'approve' : 'reject'}');
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  // ---- administración ----
  static Future<List<Map<String, dynamic>>?> adminUsers() async {
    final r = await authed('GET', '/admin/users');
    if (r == null || r.statusCode != 200) return null;
    return [for (final x in jsonDecode(r.body) as List) Map<String, dynamic>.from(x as Map)];
  }

  static Future<String?> adminCreate(String email, String tempPassword, String role, String? phone) async {
    final r = await authed('POST', '/admin/users', {'email': email, 'password': tempPassword, 'role': role, if (phone != null && phone.isNotEmpty) 'phone': phone});
    return r?.statusCode == 201 ? null : errorOf(r);
  }

  static Future<String?> adminAction(String id, String action, [Object? body]) async {
    final path = switch (action) { 'delete' => '/admin/users/$id', 'plan' => '/admin/users/$id/plan', _ => '/admin/users/$id/$action' };
    final r = await authed(action == 'delete' ? 'DELETE' : (action == 'plan' ? 'PUT' : 'POST'), path, body);
    return (r != null && r.statusCode == 200) ? null : errorOf(r);
  }

  // ---- panel de administración (v0.5) ----
  static Future<Map<String, dynamic>?> _getMap(String path) async {
    final r = await authed('GET', path);
    if (r == null || r.statusCode != 200) return null;
    final d = jsonDecode(r.body);
    return d is Map ? Map<String, dynamic>.from(d) : {'items': d};
  }

  static Future<Map<String, dynamic>?> adminStats() => _getMap('/admin/stats');
  static Future<Map<String, dynamic>?> adminSystem() => _getMap('/admin/system');
  static Future<Map<String, dynamic>?> adminAudit({String? q}) => _getMap('/admin/audit?limit=150${q == null || q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}'}');
  static Future<Map<String, dynamic>?> adminUserDetail(String id) => _getMap('/admin/users/$id');
  static Future<Map<String, dynamic>?> adminPlans() => _getMap('/admin/plans');
  static Future<Map<String, dynamic>?> adminCommunity() => _getMap('/admin/community/places');

  static Future<Map<String, dynamic>?> adminAnnouncements() => _getMap('/admin/announcements');
  static Future<Map<String, dynamic>?> myAnnouncements() => _getMap('/announcements');
  static Future<String?> adminCreateAnnouncement(String title, String body, String level, String audience, int days) async {
    final r = await authed('POST', '/admin/announcements', {'title': title, 'body': body, 'level': level, 'audience': audience, 'days': days});
    return r?.statusCode == 201 ? null : errorOf(r);
  }

  static Future<String?> adminDeleteAnnouncement(String id) async {
    final r = await authed('DELETE', '/admin/announcements/$id');
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  static Future<String?> adminPutLimits(String code, Map<String, dynamic> limits) async {
    final r = await authed('PUT', '/admin/plans/$code', {'limits': limits});
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  static Future<String?> adminSetRole(String id, String role) async {
    final r = await authed('PUT', '/admin/users/$id/role', {'role': role});
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  static Future<String?> adminDeletePlace(String id) async {
    final r = await authed('DELETE', '/admin/community/places/$id');
    return r?.statusCode == 200 ? null : errorOf(r);
  }

  // ---- salud / check-in / lugares (v0.2) ----
  static Future<List<Map<String, dynamic>>?> events() async {
    final r = await authed('GET', '/me/events');
    if (r == null || r.statusCode != 200) return null;
    return [for (final e in jsonDecode(r.body) as List) Map<String, dynamic>.from(e as Map)];
  }

  static Future<Map<String, dynamic>?> getProfile() async => _obj(await authed('GET', '/me/profile'));

  static Future<bool> putProfile(Map<String, Object?> p) async => (await authed('PUT', '/me/profile', p))?.statusCode == 200;

  /// Registra el check-in en el backend (mejor esfuerzo: el SOS por vencimiento lo dispara la app).
  static Future<void> postCheckin(String id, String label, int minutes) =>
      authed('POST', '/checkins', {'id': id, 'label': label, 'minutes': minutes});

  static Future<void> confirmCheckin(String id) => authed('POST', '/checkins/$id/confirm');
  static Future<void> finishEmergency(String id) => authed('POST', '/emergencies/$id/finish');

  /// Devuelve el id remoto del lugar o null.
  static Future<String?> postPlace(String name, double lat, double lon, int radius) async {
    final r = await authed('POST', '/places', {'name': name, 'lat': lat, 'lon': lon, 'radius_m': radius});
    return (r != null && r.statusCode == 201) ? (jsonDecode(r.body)['id'] as String) : null;
  }

  static Future<void> deletePlace(String rid) => authed('DELETE', '/places/$rid');

  // ---- recorridos y comunidad ----
  static Future<List<Map<String, dynamic>>?> _list(http.Response? r) async {
    if (r == null || r.statusCode != 200) return null;
    return [for (final e in jsonDecode(r.body) as List) Map<String, dynamic>.from(e as Map)];
  }

  static Future<List<Map<String, dynamic>>?> communityPlaces(double lat, double lon, {double radiusKm = 3}) async =>
      _list(await authed('GET', '/community/places?lat=$lat&lon=$lon&radius_km=$radiusKm'));

  static Future<Map<String, dynamic>?> addCommunityPlace(String kind, String title, String? note, double lat, double lon) async =>
      _obj(await authed('POST', '/community/places', {'kind': kind, 'title': title, 'note': note, 'lat': lat, 'lon': lon}), 201);

  static Future<Map<String, dynamic>?> voteCommunityPlace(String id, String kind) async =>
      _obj(await authed('POST', '/community/places/$id/vote', {'kind': kind}));

  static Future<void> deleteCommunityPlace(String id) => authed('DELETE', '/community/places/$id');

  static Future<List<Map<String, dynamic>>?> communityAlerts(double lat, double lon) async =>
      _list(await authed('GET', '/community/alerts?lat=$lat&lon=$lon&radius_km=3'));

  static Future<int?> respondAlert(String id) async => (_obj(await authed('POST', '/community/alerts/$id/respond')))?['responders'] as int?;

  static Future<int?> myResponders(String emergencyId) async => (_obj(await authed('GET', '/emergencies/$emergencyId/responders')))?['responders'] as int?;

  // ---- evidencia ----
  /// Sube un archivo. Devuelve el código HTTP, o null si no hay red (se reintentará).
  static Future<int?> uploadEvidence(String session, String clientId, String kind, String mime, List<int> bytes, String sha,
      {String trigger = 'manual', bool auto = false, int? durationS}) async {
    final q = 'kind=$kind&client_id=$clientId&trigger=$trigger&auto=$auto${durationS == null ? '' : '&duration_s=$durationS'}';
    final r = await authed('POST', '/emergencies/$session/evidence/upload?$q', bytes, {'Content-Type': mime, 'X-Sha256': sha});
    return r?.statusCode;
  }

  static Future<Map<String, dynamic>?> evidenceList() async => _obj(await authed('GET', '/evidence'));
  static Future<List<int>?> evidenceFile(String id) async {
    final r = await authed('GET', '/evidence/$id/file');
    return r?.statusCode == 200 ? r!.bodyBytes : null;
  }

  static Future<void> deleteEvidence(String id) => authed('DELETE', '/evidence/$id');

  // ---- ubicación en vivo y sueño ----
  static Future<Map<String, dynamic>?> liveStart(int minutes) async => _obj(await authed('POST', '/me/live', {'minutes': minutes}), 201);
  static Future<void> livePosition(double lat, double lon) => authed('POST', '/me/live/position', {'lat': lat, 'lon': lon});
  static Future<Map<String, dynamic>?> liveStatus() async => _obj(await authed('GET', '/me/live'));
  static Future<void> liveStop() => authed('DELETE', '/me/live');
  static Future<List<Map<String, dynamic>>?> sleepNights() async => _list(await authed('GET', '/health/sleep?days=30'));
}

/// Envía la cola local al backend. Idempotente por op_id; emergencias primero.
/// Devuelve true si todo lo pendiente quedó confirmado.
Future<bool> syncPending() async {
  final pending = await AegisDb.pending();
  if (pending.isEmpty) return true;
  final token = await _storage.read(key: 'access');
  if (token == null) return false;
  final items = [
    for (final p in pending)
      {'op_id': p['op_id'], 'type': p['type'], 'priority': p['priority'], 'payload': jsonDecode(p['payload'] as String)}
  ];
  try {
    Future<http.Response> send(String t) => http
        .post(Uri.parse('$apiBase/sync/batches'),
            headers: {..._json, 'Authorization': 'Bearer $t'}, body: jsonEncode({'items': items}))
        .timeout(const Duration(seconds: 20));
    var r = await send(token);
    if (r.statusCode == 401 && await Api.refresh()) r = await send((await _storage.read(key: 'access'))!);
    if (r.statusCode != 200) return false;
    for (final res in (jsonDecode(r.body)['results'] as List)) {
      await AegisDb.markOp(res['op_id'] as String, res['status'] == 'rejected' ? 'FAILED' : 'DONE');
    }
    (await SharedPreferences.getInstance()).setInt('last_sync', DateTime.now().millisecondsSinceEpoch);
    return true;
  } catch (_) {
    return false; // sin red o backend caído: queda en cola
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async => await syncPending());
}

class SyncScheduler {
  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask('sync-periodic', 'sync',
        frequency: const Duration(minutes: 15), constraints: Constraints(networkType: NetworkType.connected));
  }

  /// Tras guardar un SOS: sincroniza en cuanto haya red, con backoff exponencial.
  static Future<void> now() async => Workmanager().registerOneOffTask('sync-now-${DateTime.now().millisecondsSinceEpoch}', 'sync',
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 15));
}
