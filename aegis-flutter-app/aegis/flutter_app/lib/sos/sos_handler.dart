import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../data/db.dart';
import '../sync/sync_service.dart';

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

Future<void> notify(int id, String title, String body, {bool urgent = false}) => notifications.show(
      id,
      title,
      body,
      NotificationDetails(
          android: AndroidNotificationDetails(urgent ? 'sos' : 'info', urgent ? 'Emergencias' : 'Avisos',
              importance: urgent ? Importance.max : Importance.high, priority: urgent ? Priority.max : Priority.high)),
    );

/// Flujo SOS de la app. Orden: guardar local primero, red después. No depende de Internet, plan ni IA.
class SosHandler {
  final _handledSeq = <int>{}; // control de duplicados por reintento de la pulsera
  final _uuid = const Uuid();

  /// La app lo usa para arrancar la grabación automática (Premium). No debe bloquear nunca el SOS.
  void Function(String id, String source)? onStarted;

  /// Devuelve el id de la emergencia, o null si era un reintento duplicado de la pulsera.
  Future<String?> handle(String source, {int? seq, bool silent = false}) async {
    if (seq != null && !_handledSeq.add(seq)) return null;
    final id = _uuid.v4();
    await AegisDb.insertEmergency(id, source);
    await AegisDb.enqueue(_uuid.v4(), 'emergency', 1, jsonEncode({'id': id}));
    if (!silent) await notify(1001, 'SOS activado', 'Emergencia registrada. Si puedes, llama al 105.', urgent: true);
    SyncScheduler.now();
    try { onStarted?.call(id, source); } catch (_) {}
    // Ubicación después: si falla (GPS o permiso), el SOS ya está guardado y en cola.
    _locate(id);
    return id;
  }

  Future<void> _locate(String id) async {
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return;
      await AegisDb.setLocation(id, pos.latitude, pos.longitude);
      await AegisDb.enqueue(_uuid.v4(), 'emergency_location', 2, jsonEncode({'id': id, 'lat': pos.latitude, 'lon': pos.longitude}));
      SyncScheduler.now();
    } catch (_) {}
  }
}
