import 'evidence/recorder.dart';
import 'safety/live_share.dart';
import 'safety/pin_store.dart';
import 'safety/safe_route.dart';
import 'track/track_state.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'ble/band_client.dart';
import 'ble/protocol.dart';
import 'data/db.dart';
import 'health/reading.dart';
import 'sos/sos_handler.dart';
import 'sync/sync_service.dart';

enum NetState { online, offline }

/// Etapa de acceso: la app no muestra nada hasta llegar a [ready].
enum AuthStage { loading, loggedOut, mustChange, mfaSetup, ready }

/// Pantallas que toman toda la pantalla (caída, buscar teléfono, llamada falsa).
enum Takeover { none, fall, deviation, findPhone, fakeCall }

class CheckIn {
  final String id, label;
  final int dueMs, totalMs;
  const CheckIn(this.id, this.label, this.dueMs, this.totalMs);
}

class Place {
  final String id, name;
  final double lat, lon;
  final int radius;
  final String? rid; // id en el backend
  const Place(this.id, this.name, this.lat, this.lon, this.radius, [this.rid]);
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'lat': lat, 'lon': lon, 'radius': radius, 'rid': rid};
  factory Place.fromJson(Map<String, dynamic> j) =>
      Place(j['id'] as String, j['name'] as String, (j['lat'] as num).toDouble(), (j['lon'] as num).toDouble(), j['radius'] as int, j['rid'] as String?);
}

/// Resultado de enviar un mensaje a los contactos.
class SendOutcome {
  final bool server; // lo envió el servidor (SMS real)
  final bool composer; // se abrió la app de mensajes para que el usuario pulse enviar
  final String text;
  const SendOutcome(this.server, this.composer, this.text);
}

const adminRoles = {'SUPER_ADMIN', 'ADMIN', 'OPERADOR', 'SOPORTE'};

Map<String, dynamic> defaultSettings() => {
      'templates': [
        {'id': 'm1', 'text': 'Necesito ayuda, llámame por favor.'},
        {'id': 'm2', 'text': 'Estoy en peligro. Ven a mi ubicación.'},
        {'id': 'm3', 'text': 'Ya llegué bien.'},
        {'id': 'm4', 'text': 'Voy en camino.'},
        {'id': 'm5', 'text': 'Llego tarde, no te preocupes.'},
      ],
      'gestures': {
        'sos_double': {'action': 'message', 'message_id': 'm1'},
        'sos_triple': {'action': 'message', 'message_id': 'm2'},
        'aux_short': {'action': 'share_location'},
        'aux_double': {'action': 'checkin_ok'},
        'aux_hold': {'action': 'find_phone'},
      },
      'sos_hold_seconds': 3,
      'auto_sos_message': true,
      'fall_detection': false,
      'community_alerts': true,
      'helper_mode': true,
      'auto_record': true,
      'auto_record_triggers': ['sos', 'fall', 'tamper'],
      'step_goal': 8000,
      'sleep_goal_h': 8,
      'route_corridor_m': 300,
      'spray': {'enabled': false, 'arm_seconds': 5},
    };

/// Estado de la app. La UI solo lee esto y llama a sus métodos; no toca BLE, base de datos ni API directamente.
class AppState extends ChangeNotifier {
  final sos = SosHandler();
  late final BandClient band = BandClient(onFrame: _onFrame);
  final _uuid = const Uuid();
  final _sim = SimBand();
  final _detector = AnomalyDetector();
  final trk = TrackState();
  final rec = EvidenceRecorder();
  late final liveShare = LiveShare(trk);
  late final route = SafeRoute(trk);
  List<Map<String, Object?>> sleep = [];
  String _promptSource = 'fall';
  final community = CommunityState();

  /// Lo fija la raíz: pide permisos y arranca el servicio en primer plano.
  Future<void> Function()? onStartServices;

  // acceso y cuenta
  AuthStage stage = AuthStage.loading;
  String role = '', loginName = '';
  String? phone, mfaSecret, mfaUri;
  Uint8List? avatar;
  Map<String, dynamic> settings = defaultSettings();
  bool get isAdmin => adminRoles.contains(role);
  bool get isPremium => role == 'USER_PREMIUM';

  // conexión y sincronización
  bool bandConnected = false;
  NetState net = NetState.offline;
  int pending = 0, lastSync = 0;
  List<Map<String, Object?>> emergencies = [], contacts = [];

  // navegación, apariencia, avisos
  int tab = 0;
  ThemeMode themeMode = ThemeMode.system;
  String? banner;
  Timer? _bannerTimer;

  // salud
  Reading? latest;
  final List<Reading> live = [];
  bool demo = false;
  HrLevel? alert; // alerta de FC pendiente de respuesta del usuario
  int _lastStored = 0;

  // perfil médico, check-in, lugares
  Map<String, dynamic> profile = {};
  bool loggedIn = false;
  CheckIn? checkin;
  List<Place> places = [];

  // pantallas a pantalla completa
  Takeover takeover = Takeover.none;
  int fallSeconds = 30;
  String fakeCallName = 'Mamá';
  Timer? _takeTimer, _fakeTimer;

  Timer? _poll, _tick, _simTimer, _flush;
  SharedPreferences? _p;
  bool _servicesStarted = false, _connectivityBound = false;

  int get hrMin => (profile['hr_min'] as int?) ?? 45;
  int get hrMax => (profile['hr_max'] as int?) ?? 150;
  HrLevel get hrState => hrLevel(latest?.hr, hrMin, hrMax);
  int get checkinRemainingSec =>
      checkin == null ? 0 : ((checkin!.dueMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(0, 1 << 30).toInt();
  String get syncLabel => pending > 0 ? (net == NetState.online ? 'SYNCING' : 'PENDING') : net.name.toUpperCase();
  String get displayName {
    final n = (profile['full_name'] as String?)?.trim();
    return (n == null || n.isEmpty) ? '' : n.split(' ').first;
  }

  List<Map<String, dynamic>> get templates => [for (final t in (settings['templates'] as List)) Map<String, dynamic>.from(t as Map)];
  Map<String, dynamic> gestureCfg(String g) => Map<String, dynamic>.from(((settings['gestures'] as Map)[g] ?? {'action': 'none'}) as Map);

  // =====================================================================
  // Acceso
  // =====================================================================
  /// Grabación automática: solo Premium, solo si el usuario no la apagó y solo para los disparadores elegidos.
  bool get canAutoRecord => isPremium;
  bool _autoOn(String trigger) =>
      canAutoRecord && settings['auto_record'] != false && ((settings['auto_record_triggers'] as List?) ?? const ['sos', 'fall', 'tamper']).contains(trigger);

  void _onSosStarted(String id, String source) {
    final trig = source == 'fall' ? 'fall' : (source == 'spray' ? 'tamper' : 'sos');
    if (_autoOn(trig) && !rec.active) {
      final quiet = source == 'silent';
      rec.start(emergencyId: id, trigger: trig, auto: true, silent: quiet).then((ok) {
        if (ok && !quiet) flash('Grabando audio como evidencia');
      });
    }
  }

  /// SOS silencioso: sin sonido, sin notificación ni aviso en pantalla. Sigue la ubicación en vivo, graba (Premium)
  /// y avisa a los contactos con el enlace. Lo dispara el PIN de coacción o un gesto de la pulsera.
  Future<void> silentSos() async {
    final id = await sos.handle('silent', silent: true);
    if (id == null) return;
    refresh();
    final url = liveShare.active ? liveShare.url : await liveShare.start(minutes: 240);
    if (url != null && loggedIn && contacts.isNotEmpty) {
      final pos = await _position();
      await _pushContacts();
      await Api.sendMessage(_uuid.v4(), text: 'SOS silencioso: necesito ayuda. Sigue mi ubicación en vivo: $url', lat: pos?.latitude, lon: pos?.longitude);
    }
  }

  /// Resultado del teclado de PIN en "Estoy bien" / "falsa alarma". true = se puede cerrar la pantalla.
  Future<bool> afterPin(PinResult r) async {
    switch (r) {
      case PinResult.ok:
        return true;
      case PinResult.duress:
        silentSos(); // la pantalla se cierra como si todo estuviera bien
        return true;
      case PinResult.wrong:
        flash('PIN incorrecto');
        return false;
    }
  }

  /// Grabación bajo demanda (botón de la app o acción de un gesto de la pulsera). Premium.
  Future<String?> toggleRecording() async {
    if (rec.active) {
      await rec.stop();
      return null;
    }
    if (!canAutoRecord) return 'premium';
    final ok = await rec.start(trigger: 'manual');
    return ok ? null : (rec.error ?? 'error');
  }

  Future<void> init() async {
    sos.onStarted = _onSosStarted;
    rec.addListener(notifyListeners); // para el indicador REC
    route.onDeviation = startDeviation;
    route.onArrived = () {
      notify(1006, 'Llegaste a ${route.destName}', 'Ruta segura terminada.');
      flash('Llegaste a ${route.destName}');
    };
    final p = _p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[(p.getInt('theme') ?? 0).clamp(0, 2).toInt()];
    demo = p.getBool('demo') ?? false;
    loginName = p.getString('email') ?? '';
    role = p.getString('role') ?? '';
    final pj = p.getString('profile');
    if (pj != null) profile = Map<String, dynamic>.from(jsonDecode(pj) as Map);
    final pl = p.getString('places');
    if (pl != null) places = [for (final j in jsonDecode(pl) as List) Place.fromJson(Map<String, dynamic>.from(j as Map))];
    final sj = p.getString('settings');
    if (sj != null) settings = {...defaultSettings(), ...Map<String, dynamic>.from(jsonDecode(sj) as Map)};
    final av = p.getString('avatar_b64');
    if (av != null) avatar = base64Decode(av);
    phone = p.getString('phone');
    final cid = p.getString('ci_id');
    if (cid != null) checkin = CheckIn(cid, p.getString('ci_label') ?? 'Trayecto', p.getInt('ci_due') ?? 0, p.getInt('ci_total') ?? 0);
    if (!_connectivityBound) {
      _connectivityBound = true;
      Connectivity().onConnectivityChanged.listen((r) {
        net = r.contains(ConnectivityResult.none) ? NetState.offline : NetState.online;
        notifyListeners();
      });
    }
    loggedIn = await Api.loggedIn();
    if (!loggedIn) {
      stage = AuthStage.loggedOut;
      notifyListeners();
      return;
    }
    await _afterAuth();
  }

  /// Decide qué pantalla toca según lo que diga el servidor sobre la cuenta.
  Future<void> _afterAuth() async {
    final r = await Api.me();
    if (r == null) {
      // sin red: si ya había una sesión guardada se entra (el SOS no debe depender de Internet)
      stage = role.isEmpty ? AuthStage.loggedOut : AuthStage.ready;
    } else if (r.statusCode == 401) {
      await Api.logout();
      loggedIn = false;
      stage = AuthStage.loggedOut;
    } else if (r.statusCode == 200) {
      final o = jsonDecode(r.body) as Map<String, dynamic>;
      role = o['role'] as String? ?? role;
      loginName = o['email'] as String? ?? loginName;
      phone = o['phone'] as String?;
      loggedIn = true;
      await _p?.setString('role', role);
      if (phone != null) await _p?.setString('phone', phone!);
      if (o['must_change_password'] == true) {
        stage = AuthStage.mustChange;
      } else if (adminRoles.contains(role) && o['mfa'] != true) {
        stage = AuthStage.mfaSetup;
      } else {
        stage = AuthStage.ready;
      }
    } else {
      stage = AuthStage.loggedOut;
    }
    notifyListeners();
    if (stage == AuthStage.ready) await _enterReady();
  }

  Future<void> _enterReady() async {
    _loadRemoteAccount();
    if (!isAdmin) await _startServices();
  }

  Future<void> _loadRemoteAccount() async {
    final a = await Api.getAvatar();
    if (a != null) {
      avatar = Uint8List.fromList(a);
      await _p?.setString('avatar_b64', base64Encode(a));
      notifyListeners();
    }
    if (!isAdmin) {
      final s = await Api.getSettings();
      if (s != null) {
        settings = {...defaultSettings(), ...s};
        await _p?.setString('settings', jsonEncode(settings));
        notifyListeners();
        _pushBandConfig();
      }
      syncProfile();
    }
  }

  Future<void> _startServices() async {
    if (_servicesStarted) return;
    _servicesStarted = true;
    if (onStartServices != null) await onStartServices!();
    band.connected.stream.listen((c) {
      bandConnected = c;
      if (c) {
        if (demo) setDemo(false); // con la pulsera real conectada, el simulador sobra
        _pushBandConfig();
        band.send(Proto.tCommand, Proto.timeSync(DateTime.now().millisecondsSinceEpoch ~/ 1000));
      }
      notifyListeners();
    });
    await band.start();
    await trk.recoverInterrupted();
    await community.loadCache();
    community.startAlertPolling(trk.position, () => settings['helper_mode'] != false);
    liveShare.restore();
    await loadSleep();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _flush = Timer.periodic(const Duration(minutes: 2), (_) { flushHealth(); rec.flush(); });
    if (demo) _startSim();
    AegisDb.pruneReadings();
    await _restoreLive();
    await refresh();
  }

  /// Devuelve un código de error (invalid_credentials, totp_required, invalid_totp, account_suspended,
  /// too_many_attempts, network…) o null si entró.
  Future<String?> login(String user, String pw, String? totp) async {
    final r = await Api.login(user.trim(), pw, totp);
    if (!r.ok) return r.error;
    // otra persona en el mismo teléfono: no heredar datos ni colas pendientes de la anterior
    final owner = _p?.getString('owner');
    final me = user.trim().toLowerCase();
    if (owner != null && owner != me) await _wipeLocal();
    await _p?.setString('owner', me);
    loggedIn = true;
    loginName = user.trim();
    role = r.role;
    await _afterAuth();
    return null;
  }

  /// Cambio de contraseña (obligatorio en el primer ingreso o tras un restablecimiento). Devuelve código de error o null.
  Future<String?> changePassword(String current, String next) async {
    final e = await Api.changePassword(current, next);
    if (e != null) return e;
    await _afterAuth();
    return null;
  }

  Future<bool> startMfa() async {
    final o = await Api.mfaSetup();
    if (o == null) return false;
    mfaSecret = o['secret'] as String?;
    mfaUri = o['otpauth_uri'] as String?;
    notifyListeners();
    return true;
  }

  Future<bool> verifyMfa(String code) async {
    if (!await Api.mfaVerify(code.trim())) return false;
    mfaSecret = mfaUri = null;
    await _afterAuth();
    return true;
  }

  Future<void> signOut() async {
    _poll?.cancel();
    _tick?.cancel();
    _simTimer?.cancel();
    _flush?.cancel();
    stopTakeover();
    await liveShare.stop();
    route.reset();
    await trk.stop();
    await rec.stop();
    await band.stop();
    _servicesStarted = false;
    await Api.logout();
    loggedIn = false;
    role = '';
    tab = 0;
    stage = AuthStage.loggedOut;
    notifyListeners();
  }

  Future<void> _wipeLocal() async {
    await AegisDb.wipe();
    await liveShare.reset();
    route.reset();
    await PinStore.clear();
    sleep = [];
    await trk.reset();
    await rec.reset();
    await community.reset();
    final p = _p!;
    for (final k in ['profile', 'places', 'settings', 'avatar_b64', 'phone', 'ci_id', 'ci_label', 'ci_due', 'ci_total', 'last_sync']) {
      await p.remove(k);
    }
    profile = {};
    places = [];
    settings = defaultSettings();
    avatar = null;
    phone = null;
    checkin = null;
    latest = null;
    live.clear();
    contacts = [];
    emergencies = [];
  }

  // =====================================================================
  // Pulsera
  // =====================================================================
  Future<void> _restoreLive() async {
    final rs = await AegisDb.readingsSince(DateTime.now().subtract(const Duration(minutes: 10)).millisecondsSinceEpoch);
    live..clear()..addAll(rs.length > 150 ? rs.sublist(rs.length - 150) : rs);
    if (live.isNotEmpty) latest = live.last;
  }

  void _onFrame(Frame f) {
    switch (f.type) {
      case Proto.tSosStart:
        band.sendAck(f.seq); // ACK inmediato: la pulsera deja de reintentar
        sos.handle('band', seq: f.seq).then((_) => refresh());
      case Proto.tSosCancel:
        band.sendAck(f.seq);
      case Proto.tHealth:
        final s = Proto.decodeHealth(f);
        if (s != null) _ingest(Reading.fromSample(s));
      case Proto.tButton:
        if (f.payload.isNotEmpty) _onGesture(f.payload[0]);
      case Proto.tSleep:
        if (f.payload.length >= 9) {
          final b = ByteData.sublistView(Uint8List.fromList(f.payload));
          saveSleep(DateTime.fromMillisecondsSinceEpoch(b.getUint32(0, Endian.little) * 1000),
              DateTime.fromMillisecondsSinceEpoch(b.getUint32(4, Endian.little) * 1000), quality: b.getUint8(8), source: 'band');
        }
      case Proto.tBandAlert:
        if (f.payload.isNotEmpty) _onBandAlert(f.payload[0], f.payload.length > 1 ? f.payload[1] : 0);
    }
  }

  void _onGesture(int g) {
    final name = Proto.gestureNames[g];
    if (name == null) return;
    final cfg = gestureCfg(name);
    runAction(cfg['action'] as String? ?? 'none', messageId: cfg['message_id'] as String?, gesture: name);
  }

  void _onBandAlert(int code, int value) {
    _logEvent('band_alert', {'code': code, 'value': value});
    switch (code) {
      case Proto.aFall:
        if (settings['fall_detection'] == true) startFall();
      case Proto.aLowBattery:
        notify(1004, 'Batería de la pulsera baja', 'Queda $value %. Cárgala pronto.');
        flash('Batería de la pulsera: $value %');
      case Proto.aTamper:
        flash('Alguien manipuló la pulsera');
        if (_autoOn('tamper') && !rec.active) rec.start(trigger: 'tamper', auto: true);
      case Proto.aOffWrist:
        flash('La pulsera se quitó de la muñeca');
      case Proto.aSprayFired:
        sos.handle('spray').then((_) => refresh()); // un disparo siempre implica peligro
        flash('Módulo de defensa activado: se pidió ayuda');
      case Proto.aSprayArmed:
        flash('Módulo de defensa armado');
      case Proto.aSprayDisarmed:
        flash('Módulo de defensa desarmado');
    }
  }

  /// Ejecuta la acción asignada a un gesto de la pulsera (o a un botón de la app).
  Future<void> runAction(String action, {String? messageId, String? gesture}) async {
    if (gesture != null) _logEvent('gesture', {'gesture': gesture, 'action': action});
    HapticFeedback.mediumImpact();
    switch (action) {
      case 'sos':
        await sos.handle('band-action');
        await refresh();
      case 'message':
        if (messageId == null) return;
        final o = await sendTemplate(messageId);
        flash(_outcomeText(o));
      case 'share_location':
        flash(_outcomeText(await shareLocation()));
      case 'checkin_ok':
        if (checkin != null) {
          await confirmCheckin();
          flash('Check-in confirmado');
        } else {
          flash('No hay un check-in activo');
        }
      case 'find_phone':
        startFindPhone();
      case 'fake_call':
        startFakeCall(delaySeconds: 0);
      case 'silent_sos':
        await silentSos();
      case 'live_share':
        if (liveShare.active) {
          await liveShare.stop();
          flash('Dejaste de compartir tu ubicación');
        } else {
          final u = await liveShare.start();
          flash(u == null ? 'No se pudo compartir la ubicación' : 'Compartiendo tu ubicación en vivo');
        }
      case 'record':
        final e = await toggleRecording();
        flash(e == 'premium' ? 'Grabar evidencia es una función Premium' : (e != null ? e : (rec.active ? 'Grabando audio' : 'Grabación guardada')));
      default:
        break;
    }
  }

  String _outcomeText(SendOutcome o) => o.server ? 'Mensaje enviado a tus contactos' : (o.composer ? 'Se abrió tu app de mensajes: pulsa enviar' : o.text);

  void _logEvent(String kind, Map<String, Object?> data) {
    AegisDb.enqueue(_uuid.v4(), 'device_event', 4, jsonEncode({'kind': kind, ...data, 'ts': DateTime.now().toUtc().toIso8601String()}));
  }

  /// Envía la configuración a la pulsera (se reenvía al reconectar).
  void _pushBandConfig() {
    if (!bandConnected) return;
    final sp = Map<String, dynamic>.from((settings['spray'] ?? {}) as Map);
    band.send(Proto.tConfig, Proto.config(
        sosHoldSeconds: (settings['sos_hold_seconds'] as int?) ?? 3,
        fall: settings['fall_detection'] == true,
        spray: sp['enabled'] == true,
        armSeconds: (sp['arm_seconds'] as int?) ?? 5));
  }

  Future<String?> saveSettings(Map<String, dynamic> s) async {
    settings = {...settings, ...s};
    await _p?.setString('settings', jsonEncode(settings));
    notifyListeners();
    _pushBandConfig();
    if (!loggedIn) return null;
    return Api.putSettings(settings);
  }

  Future<void> ringBand() async {
    final ok = await band.send(Proto.tCommand, Proto.command(Proto.cmdFind, 10));
    flash(ok ? 'Tu pulsera está sonando' : 'La pulsera no está conectada');
  }

  void _ingest(Reading r) {
    latest = r;
    live.add(r);
    if (live.length > 150) live.removeAt(0);
    if (r.ts - _lastStored >= 10000) {
      _lastStored = r.ts; // 1 lectura cada 10 s en disco; la gráfica en vivo las ve todas
      AegisDb.insertReading(r);
    }
    final lvl = _detector.feed(r.hr, hrMin, hrMax, r.ts);
    if (lvl != null) {
      alert = lvl;
      notify(1002, lvl == HrLevel.high ? 'Frecuencia cardíaca alta' : 'Frecuencia cardíaca baja',
          '${r.hr} lpm. Abre AEGIS para confirmar que estás bien.', urgent: true);
    }
    notifyListeners();
  }

  void dismissAlert() {
    alert = null;
    notifyListeners();
  }

  /// Envía a la cola de sincronización las lecturas reales acumuladas (solo con sesión iniciada).
  Future<void> flushHealth() async {
    if (!loggedIn) return;
    final rs = await AegisDb.unqueuedReadings(200);
    if (rs.isEmpty) return;
    await AegisDb.enqueue(_uuid.v4(), 'telemetry', 5, jsonEncode({'readings': [for (final r in rs) r.toApi()]}));
    await AegisDb.markQueued(rs);
    SyncScheduler.now();
  }

  // ---------- modo demostración ----------
  Future<void> setDemo(bool v) async {
    demo = v;
    await _p?.setBool('demo', v);
    v ? _startSim() : _simTimer?.cancel();
    notifyListeners();
  }

  void _startSim() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(seconds: 2), (_) => _ingest(Reading.fromSample(_sim.next(), source: 'sim')));
  }

  /// Fuerza un pico de FC en el simulador para enseñar la alerta.
  void simulateSpike() {
    if (!demo) return;
    for (var i = 0; i < 4; i++) {
      Future.delayed(Duration(milliseconds: 300 * i), () => _ingest(Reading.fromSample(_sim.next(forceHr: hrMax + 25), source: 'sim')));
    }
  }

  /// Lecturas del rango pedido, reducidas a ≤160 puntos para dibujar.
  Future<List<Reading>> loadRange(Duration d) async {
    final rs = await AegisDb.readingsSince(DateTime.now().subtract(d).millisecondsSinceEpoch);
    const maxPts = 160;
    if (rs.length <= maxPts) return rs;
    final step = rs.length / maxPts;
    final out = <Reading>[];
    for (var i = 0; i < maxPts; i++) {
      final chunk = rs.sublist((i * step).floor(), ((i + 1) * step).floor().clamp(1, rs.length).toInt());
      if (chunk.isEmpty) continue;
      final hrs = [for (final r in chunk) if (r.hr != null) r.hr!];
      out.add(Reading(
          clientId: chunk.last.clientId, ts: chunk.last.ts,
          hr: hrs.isEmpty ? null : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
          spo2: chunk.last.spo2, tempC: chunk.last.tempC, steps: chunk.last.steps, battery: chunk.last.battery,
          source: chunk.last.source));
    }
    return out;
  }

  // =====================================================================
  // Pantallas a pantalla completa: caída, buscar teléfono, llamada falsa
  // =====================================================================
  void startFall() => _startPrompt(Takeover.fall, 'fall', '¿Te caíste?', 'Confirma que estás bien o se activará un SOS.');

  /// Te saliste de la ruta segura: misma cuenta atrás que la caída.
  void startDeviation() => _startPrompt(Takeover.deviation, 'deviation', '¿Todo bien?', 'Te alejaste de tu ruta segura. Confirma o se activará un SOS.');

  void _startPrompt(Takeover kind, String source, String title, String body) {
    if (takeover == Takeover.fall || takeover == Takeover.deviation) return;
    _takeTimer?.cancel();
    takeover = kind;
    _promptSource = source;
    fallSeconds = 30;
    HapticFeedback.heavyImpact();
    notify(1005, title, body, urgent: true);
    _takeTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      fallSeconds--;
      HapticFeedback.vibrate();
      if (fallSeconds <= 0) {
        t.cancel();
        takeover = Takeover.none;
        notifyListeners();
        await sos.handle(source);
        await refresh();
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> fallNeedHelp() async {
    final src = _promptSource;
    stopTakeover();
    await sos.handle(src);
    await refresh();
  }

  void startFindPhone() {
    _takeTimer?.cancel();
    takeover = Takeover.findPhone;
    var n = 0;
    _takeTimer = Timer.periodic(const Duration(milliseconds: 1200), (t) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      if (++n > 25) stopTakeover(); // 30 s como máximo
    });
    notifyListeners();
  }

  /// Llamada entrante falsa para salir de una situación incómoda.
  void startFakeCall({int delaySeconds = 10, String? name}) {
    _fakeTimer?.cancel();
    if (name != null) fakeCallName = name;
    void show() {
      _takeTimer?.cancel();
      takeover = Takeover.fakeCall;
      _takeTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.vibrate();
      });
      notifyListeners();
    }

    if (delaySeconds <= 0) {
      show();
    } else {
      flash('Llamada falsa en $delaySeconds s');
      _fakeTimer = Timer(Duration(seconds: delaySeconds), show);
    }
  }

  /// Contestar la llamada falsa: deja de sonar pero la pantalla sigue.
  void answerFakeCall() {
    _takeTimer?.cancel();
    notifyListeners();
  }

  void stopTakeover() {
    _takeTimer?.cancel();
    _fakeTimer?.cancel();
    takeover = Takeover.none;
    notifyListeners();
  }

  void simulateFall() => startFall();

  /// Aviso breve en la parte superior de la pantalla.
  void flash(String msg) {
    banner = msg;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      banner = null;
      notifyListeners();
    });
    notifyListeners();
  }

  // =====================================================================
  // Check-in
  // =====================================================================
  void _onTick() {
    if (checkin != null) {
      if (checkinRemainingSec <= 0) {
        _expireCheckin();
      } else {
        notifyListeners();
      }
    }
  }

  Future<void> startCheckin(String label, int minutes) async {
    final id = _uuid.v4();
    final due = DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch;
    checkin = CheckIn(id, label, due, minutes * 60000);
    await _saveCheckin();
    Api.postCheckin(id, label, minutes);
    notifyListeners();
  }

  Future<void> extendCheckin(int minutes) async {
    final c = checkin;
    if (c == null) return;
    checkin = CheckIn(c.id, c.label, c.dueMs + minutes * 60000, c.totalMs + minutes * 60000);
    await _saveCheckin();
    notifyListeners();
  }

  Future<void> confirmCheckin() async {
    final c = checkin;
    if (c == null) return;
    checkin = null;
    await _saveCheckin();
    Api.confirmCheckin(c.id);
    notifyListeners();
  }

  Future<void> _expireCheckin() async {
    final c = checkin;
    if (c == null) return;
    checkin = null; // primero se limpia: así el SOS no se dispara dos veces
    await _saveCheckin();
    await sos.handle('checkin');
    await notify(1003, 'Check-in vencido', '"${c.label}" no se confirmó: se activó un SOS.', urgent: true);
    await refresh();
  }

  Future<void> _saveCheckin() async {
    final p = _p!;
    final c = checkin;
    if (c == null) {
      for (final k in ['ci_id', 'ci_label', 'ci_due', 'ci_total']) {
        await p.remove(k);
      }
    } else {
      await p.setString('ci_id', c.id);
      await p.setString('ci_label', c.label);
      await p.setInt('ci_due', c.dueMs);
      await p.setInt('ci_total', c.totalMs);
    }
  }

  // =====================================================================
  // SOS, contactos y mensajes
  // =====================================================================
  Future<String?> sosFromScreen() async {
    final id = await sos.handle('screen');
    await refresh();
    return id;
  }

  Future<void> markFalseAlarm(String id) async {
    await AegisDb.setEmergencyStatus(id, 'CANCELLED');
    Api.finishEmergency(id); // mejor esfuerzo; si aún no se sincronizó, el backend responde 404 y se ignora
    await refresh();
  }

  Future<void> addContact(String n, String p) async {
    await AegisDb.addContact(n, p);
    await refresh();
    _pushContacts();
  }

  Future<void> removeContact(int id) async {
    contacts = contacts.where((c) => c['id'] != id).toList(); // quita ya de la lista (Dismissible lo exige)
    notifyListeners();
    await AegisDb.removeContact(id);
    await refresh();
    _pushContacts();
  }

  /// Copia la lista de contactos al servidor para que él pueda avisarles (mejor esfuerzo).
  Future<void> _pushContacts() async {
    if (!loggedIn) return;
    final e = await Api.pushContacts(await AegisDb.contacts());
    if (e == 'plan_limit_contacts') flash('Tu plan no permite tantos contactos: el servidor no los avisará a todos');
  }

  Future<Position?> _position() async {
    final l = trk.last;
    if (trk.active && l != null && DateTime.now().difference(l.timestamp).inSeconds < 60) return l;
    try {
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  String _digits(String n) => n.replaceAll(RegExp(r'[^0-9+]'), '');

  /// Abre la app de SMS con el texto para todos los contactos (el usuario pulsa enviar).
  Future<bool> _composeSms(String text, Position? pos) async {
    if (contacts.isEmpty) return false;
    final link = pos == null ? '' : ' Ubicación: https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    final nums = [for (final c in contacts) _digits(c['phone'] as String)].join(',');
    return launchUrl(Uri.parse('sms:$nums?body=${Uri.encodeComponent('$text$link')}'));
  }

  Future<SendOutcome> _send({String? templateId, required String text}) async {
    if (contacts.isEmpty) return const SendOutcome(false, false, 'Agrega contactos primero');
    final pos = await _position();
    if (loggedIn) {
      await _pushContacts(); // el servidor necesita la lista actual
      final (res, err) = await Api.sendMessage(_uuid.v4(), templateId: templateId, text: templateId == null ? text : null, lat: pos?.latitude, lon: pos?.longitude);
      if (err == null && res.any((r) => r['status'] == 'SENT')) return SendOutcome(true, false, text);
      if (err == 'plan_limit_messages') return const SendOutcome(false, false, 'Llegaste al límite diario de mensajes de tu plan');
    }
    // sin proveedor SMS en el servidor, sin red o con error: se abre la app de mensajes del teléfono
    return SendOutcome(false, await _composeSms(text, pos), text);
  }

  Future<SendOutcome> sendTemplate(String id) {
    final t = templates.where((x) => x['id'] == id).toList();
    if (t.isEmpty) return Future.value(const SendOutcome(false, false, 'Mensaje no encontrado'));
    return _send(templateId: id, text: t.first['text'] as String);
  }

  /// Manda el enlace de ubicación en vivo a los contactos (servidor o app de SMS). Devuelve un texto para mostrar.
  Future<String> sendLiveLink() async {
    final u = liveShare.url;
    if (u == null) return 'No hay un enlace activo';
    return _outcomeText(await _send(text: 'Sigue mi ubicación en vivo: $u'));
  }

  Future<SendOutcome> shareLocation() => _send(text: 'Te comparto mi ubicación.');

  /// Aviso tras un SOS: abre la app de mensajes con la alerta.
  Future<bool> alertContacts({bool sosActive = false}) async {
    if (contacts.isEmpty) return false;
    final who = (profile['full_name'] as String?)?.trim();
    final head = sosActive ? 'EMERGENCIA: necesito ayuda' : 'Te comparto mi ubicación';
    return _composeSms('$head${who == null || who.isEmpty ? '' : ' ($who)'}.', await _position());
  }

  Future<List<Map<String, dynamic>>> messageHistory() => Api.messageHistory();

  // ---------- lugares seguros ----------
  Future<String?> addPlaceHere(String name, int radius) async {
    final pos = await _position();
    if (pos == null) return 'No se pudo obtener tu ubicación. Activa el GPS y el permiso.';
    final id = _uuid.v4();
    String? rid;
    if (loggedIn) rid = await Api.postPlace(name, pos.latitude, pos.longitude, radius);
    places = [...places, Place(id, name, pos.latitude, pos.longitude, radius, rid)];
    await _p?.setString('places', jsonEncode([for (final x in places) x.toJson()]));
    notifyListeners();
    return null;
  }

  Future<void> removePlace(String id) async {
    final pl = places.where((x) => x.id == id).toList();
    if (pl.isNotEmpty && pl.first.rid != null) Api.deletePlace(pl.first.rid!);
    places = places.where((x) => x.id != id).toList();
    await _p?.setString('places', jsonEncode([for (final x in places) x.toJson()]));
    notifyListeners();
  }

  Future<Position?> currentPosition() => _position();

  // =====================================================================
  // Perfil
  // =====================================================================
  Future<bool> saveProfile(Map<String, dynamic> p) async {
    profile = {...profile, ...p};
    await _p?.setString('profile', jsonEncode(profile));
    notifyListeners();
    if (!loggedIn) return false;
    return Api.putProfile({
      for (final k in ['full_name', 'birth_year', 'blood_type', 'allergies', 'conditions', 'medications', 'notes', 'hr_min', 'hr_max'])
        k: profile[k]
    });
  }

  /// Si hay datos en el servidor se usan; si el servidor está vacío, se sube lo local.
  Future<void> syncProfile() async {
    final srv = await Api.getProfile();
    if (srv == null) return;
    final hasServer = ['full_name', 'blood_type', 'allergies', 'conditions', 'medications', 'notes'].any((k) => srv[k] != null);
    if (hasServer) {
      profile = {for (final k in ['full_name', 'birth_year', 'blood_type', 'allergies', 'conditions', 'medications', 'notes', 'hr_min', 'hr_max']) k: srv[k]};
      await _p?.setString('profile', jsonEncode(profile));
      notifyListeners();
    } else if (profile.isNotEmpty) {
      await saveProfile(profile);
    }
  }

  Future<String?> savePhone(String v) async {
    final e = await Api.putPhone(v.trim().isEmpty ? null : v.trim());
    if (e != null) return e;
    phone = v.trim().isEmpty ? null : v.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    phone == null ? await _p?.remove('phone') : await _p?.setString('phone', phone!);
    notifyListeners();
    return null;
  }

  Future<String?> setAvatar(Uint8List bytes, String mime) async {
    final e = await Api.putAvatar(bytes, mime);
    if (e != null) return e;
    avatar = bytes;
    await _p?.setString('avatar_b64', base64Encode(bytes));
    notifyListeners();
    return null;
  }

  Future<void> removeAvatar() async {
    await Api.deleteAvatar();
    avatar = null;
    await _p?.remove('avatar_b64');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _p?.setInt('theme', m.index);
    notifyListeners();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  Future<void> syncNow() async {
    await flushHealth();
    await syncPending();
    rec.flush();
    await refresh();
  }

  Future<void> refresh() async {
    pending = await AegisDb.pendingCount();
    emergencies = [for (final e in await AegisDb.emergencies()) if (!(e['source'] == 'silent' && e['status'] == 'ACTIVE')) e];
    contacts = await AegisDb.contacts();
    lastSync = (await SharedPreferences.getInstance()).getInt('last_sync') ?? 0;
    notifyListeners();
  }

  Future<void> rescanBand() => band.rescan();

  // =====================================================================
  // Metas: pasos y sueño
  // =====================================================================
  int get stepGoal => (settings['step_goal'] as num?)?.toInt() ?? 8000;
  double get sleepGoalH => (settings['sleep_goal_h'] as num?)?.toDouble() ?? 8;

  /// Pasos de hoy: el contador diario de la pulsera (el mayor del día).
  Future<int> todaySteps() async {
    final n = DateTime.now();
    final rs = await AegisDb.readingsSince(DateTime(n.year, n.month, n.day).millisecondsSinceEpoch);
    var m = 0;
    for (final r in rs) {
      if ((r.steps ?? 0) > m) m = r.steps!;
    }
    return m;
  }

  Future<void> loadSleep() async {
    sleep = await AegisDb.sleepNights(14);
    notifyListeners();
    final remote = await Api.sleepNights();
    if (remote != null && remote.isNotEmpty) {
      for (final r in remote) {
        final st = DateTime.tryParse('${r['start_ts']}'), en = DateTime.tryParse('${r['end_ts']}');
        if (st == null || en == null) continue;
        await AegisDb.saveSleep({'night': r['night'], 'start': st.millisecondsSinceEpoch, 'end_': en.millisecondsSinceEpoch, 'minutes': r['minutes'], 'quality': r['quality'], 'source': r['source'] ?? 'manual'});
      }
      sleep = await AegisDb.sleepNights(14);
      notifyListeners();
    }
  }

  /// Guarda una noche (la fecha es la del despertar). Se sincroniza cuando hay red.
  Future<String?> saveSleep(DateTime start, DateTime end, {int? quality, String source = 'manual'}) async {
    final mins = end.difference(start).inMinutes;
    if (mins < 20 || mins > 18 * 60) return 'invalid_sleep_range';
    final night = '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    await AegisDb.saveSleep({'night': night, 'start': start.millisecondsSinceEpoch, 'end_': end.millisecondsSinceEpoch, 'minutes': mins, 'quality': quality, 'source': source});
    await AegisDb.enqueue(_uuid.v4(), 'sleep', 6, jsonEncode({'night': night, 'start_ts': start.toUtc().toIso8601String(), 'end_ts': end.toUtc().toIso8601String(), 'quality': quality, 'source': source}));
    SyncScheduler.now();
    sleep = await AegisDb.sleepNights(14);
    notifyListeners();
    return null;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _simTimer?.cancel();
    _flush?.cancel();
    _takeTimer?.cancel();
    _fakeTimer?.cancel();
    _bannerTimer?.cancel();
    liveShare.dispose();
    route.dispose();
    trk.dispose();
    rec.dispose();
    community.dispose();
    band.stop();
    super.dispose();
  }
}
