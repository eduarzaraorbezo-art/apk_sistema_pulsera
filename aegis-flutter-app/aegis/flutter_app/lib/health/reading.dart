import 'dart:math';
import 'package:uuid/uuid.dart';
import '../ble/protocol.dart';

const _uuid = Uuid();

/// Una lectura de salud (de la pulsera o del simulador).
class Reading {
  final String clientId;
  final int ts; // epoch ms
  final int? hr, spo2, steps, battery;
  final double? tempC;
  final String source; // 'band' | 'sim'

  Reading({String? clientId, required this.ts, this.hr, this.spo2, this.tempC, this.steps, this.battery, this.source = 'band'})
      : clientId = clientId ?? _uuid.v4();

  factory Reading.fromSample(HealthSample s, {String source = 'band', int? ts}) => Reading(
      ts: ts ?? DateTime.now().millisecondsSinceEpoch,
      hr: s.hr, spo2: s.spo2, tempC: s.tempC, steps: s.steps, battery: s.battery, source: source);

  factory Reading.fromMap(Map<String, Object?> m) => Reading(
      clientId: m['client_id'] as String,
      ts: m['ts'] as int,
      hr: m['hr'] as int?,
      spo2: m['spo2'] as int?,
      tempC: (m['temp'] as num?)?.toDouble(),
      steps: m['steps'] as int?,
      battery: m['battery'] as int?,
      source: (m['source'] as String?) ?? 'band');

  Map<String, Object?> toMap() => {
        'client_id': clientId, 'ts': ts, 'hr': hr, 'spo2': spo2, 'temp': tempC,
        'steps': steps, 'battery': battery, 'source': source,
      };

  Map<String, Object?> toApi() => {
        'client_id': clientId,
        'ts': DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toIso8601String(),
        if (hr != null) 'hr': hr,
        if (spo2 != null) 'spo2': spo2,
        if (tempC != null) 'temp_c': tempC,
        if (steps != null) 'steps': steps,
        if (battery != null) 'battery': battery,
        'source': source,
      };
}

/// Estado de la frecuencia cardíaca respecto a los umbrales del usuario.
enum HrLevel { none, low, normal, high }

HrLevel hrLevel(int? hr, int min, int max) {
  if (hr == null) return HrLevel.none;
  if (hr < min) return HrLevel.low;
  if (hr > max) return HrLevel.high;
  return HrLevel.normal;
}

/// Dispara una alerta tras [needed] lecturas consecutivas fuera de rango (evita falsas alarmas por una lectura ruidosa)
/// y respeta un enfriamiento para no repetir la alerta.
class AnomalyDetector {
  AnomalyDetector({this.needed = 3, this.cooldownMs = 5 * 60 * 1000});
  final int needed, cooldownMs;
  int _streak = 0;
  HrLevel _last = HrLevel.normal;
  int _lastAlertTs = -1 << 40;

  /// Devuelve el nivel (low/high) si hay que alertar ahora; null si no.
  HrLevel? feed(int? hr, int min, int max, int nowMs) {
    final l = hrLevel(hr, min, max);
    if (l == HrLevel.none) return null;
    if (l == HrLevel.normal) {
      _streak = 0;
      _last = l;
      return null;
    }
    _streak = (l == _last) ? _streak + 1 : 1;
    _last = l;
    if (_streak >= needed && nowMs - _lastAlertTs >= cooldownMs) {
      _lastAlertTs = nowMs;
      return l;
    }
    return null;
  }
}

/// Simulador para demostraciones sin pulsera. Marca las lecturas como 'sim' y no se envían al backend.
class SimBand {
  final _rnd = Random();
  double _hr = 72;
  int _steps = 0;
  double _bat = 92;
  double _target = 72;

  /// [boost] permite forzar un pico (para demostrar la alerta).
  HealthSample next({int? forceHr}) {
    if (forceHr != null) {
      _hr = forceHr.toDouble();
    } else {
      if (_rnd.nextInt(25) == 0) _target = 62 + _rnd.nextInt(40);
      _hr += (_target - _hr) * 0.15 + (_rnd.nextDouble() - 0.5) * 3;
    }
    _steps += _rnd.nextInt(5);
    _bat = max(5, _bat - 0.002);
    return HealthSample(
        hr: _hr.round(),
        spo2: 96 + _rnd.nextInt(3),
        tempC: 36.4 + _rnd.nextDouble() * 0.5,
        steps: _steps,
        battery: _bat.round());
  }
}
