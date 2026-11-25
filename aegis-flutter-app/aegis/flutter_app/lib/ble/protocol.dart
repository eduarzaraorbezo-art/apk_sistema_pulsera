import 'dart:typed_data';

/// Protocolo BLE AEGIS v1. Debe coincidir con firmware/main/protocol.c.
class Frame {
  final int type, flags, seq;
  final Uint8List payload;
  const Frame(this.type, this.flags, this.seq, this.payload);
}

/// Muestra de salud enviada por la pulsera. Un campo null = sensor sin lectura.
class HealthSample {
  final int? hr, spo2, steps, battery;
  final double? tempC;
  const HealthSample({this.hr, this.spo2, this.tempC, this.steps, this.battery});
}

class Proto {
  static const version = 1;
  static const headerSize = 7; // ver, tipo, flags, seq(2 LE), len(2 LE)
  static const tSosStart = 1, tSosCancel = 2, tAck = 10, tHeartbeat = 11, tHealth = 12;
  // v1.1 (ver docs/PROTOCOLO_PULSERA.md)
  static const tButton = 13; // pulsera→app: [gesto]
  static const tConfig = 14; // app→pulsera: [sos_hold_s, flags, arm_s]
  static const tCommand = 15; // app→pulsera: [cmd, arg, ...]
  static const tBandAlert = 16; // pulsera→app: [código, valor]

  // gestos del botón (1-5 se delegan a la app según la configuración; mantener SOS = SOS_START fijo en el firmware)
  static const gSosDouble = 1, gSosTriple = 2, gAuxShort = 3, gAuxDouble = 4, gAuxHold = 5;
  static const gestureNames = {gSosDouble: 'sos_double', gSosTriple: 'sos_triple', gAuxShort: 'aux_short', gAuxDouble: 'aux_double', gAuxHold: 'aux_hold'};

  // comandos app→pulsera
  static const cmdFind = 1, cmdVibrate = 2, cmdTimeSync = 3, cmdSprayDisarm = 4, cmdRecStart = 5, cmdRecStop = 6, cmdSnapshot = 7;
  // alertas pulsera→app
  static const aFall = 1, aLowBattery = 2, aOffWrist = 3, aTamper = 4, aSprayArmed = 5, aSprayFired = 6, aSprayDisarmed = 7, aRecStarted = 8, aRecStopped = 9, aMediaReady = 10;
  static const tSleep = 18; // pulsera→app: noche de sueño [inicio u32 epoch, fin u32 epoch, calidad u8]
  static const tMedia = 17; // pulsera→app: trozo de archivo [fileId u16, offset u32, total u32, kind u8, datos…] (reservado)
  // flags de tConfig
  static const cfgFall = 1, cfgSpray = 2, cfgHaptic = 4;
  // v1.1: gestos de botones, feedback hacia la pulsera y módulo de defensa (reservado)
  static const tGesture = 20; // pulsera -> app, payload: [gestureId]
  static const tFeedback = 30; // app -> pulsera, payload: [patternId]
  static const tFindBand = 31; // app -> pulsera, payload: [segundos]
  static const tSprayEvent = 40; // pulsera -> app, payload: [estado] 0 armado, 1 disparado, 2 desarmado, 3 fallo

  // Patrones de feedback: vibración + LED
  static const fbOk = 1, fbError = 2, fbSent = 3, fbArmed = 4;
  static const healthPayloadLen = 9; // hr u8, spo2 u8, temp u16 LE (0.01 °C), steps u32 LE, battery u8

  static const svcControl = 'aab5d599-d6ce-40dd-aca0-d30900dbf06c';
  static const charSosEvent = '63d6e2d3-41fb-432b-9616-3ff24c71e21c'; // Indicate
  static const charCommand = 'c88eee2d-db0b-4e3c-ab49-beda32892c6c'; // Write
  static const charCommandResp = '37e43c76-e731-4ebc-889b-4c4b5f4ba563'; // Indicate
  static const charStatus = '6fd6aae5-8d22-4e72-bd04-b81478c78983'; // Read/Notify (tHealth)

  /// CRC-16/CCITT-FALSE
  static int crc16(List<int> d, [int? len]) {
    var crc = 0xFFFF;
    final n = len ?? d.length;
    for (var i = 0; i < n; i++) {
      crc ^= (d[i] & 0xFF) << 8;
      for (var b = 0; b < 8; b++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc;
  }

  static Uint8List encode(Frame f) {
    final out = Uint8List(headerSize + f.payload.length + 2);
    out[0] = version;
    out[1] = f.type;
    out[2] = f.flags;
    out[3] = f.seq & 0xFF;
    out[4] = (f.seq >> 8) & 0xFF;
    out[5] = f.payload.length & 0xFF;
    out[6] = (f.payload.length >> 8) & 0xFF;
    out.setRange(headerSize, headerSize + f.payload.length, f.payload);
    final crc = crc16(out, headerSize + f.payload.length);
    out[out.length - 2] = crc & 0xFF;
    out[out.length - 1] = (crc >> 8) & 0xFF;
    return out;
  }

  /// null si versión, longitud o CRC son inválidos.
  static Frame? decode(List<int> b) {
    if (b.length < headerSize + 2 || b[0] != version) return null;
    final len = b[5] | (b[6] << 8);
    if (b.length != headerSize + len + 2) return null;
    final crc = b[b.length - 2] | (b[b.length - 1] << 8);
    if (crc != crc16(b, headerSize + len)) return null;
    return Frame(b[1], b[2], b[3] | (b[4] << 8), Uint8List.fromList(b.sublist(headerSize, headerSize + len)));
  }

  static Uint8List feedback(int seq, int pattern) => encode(Frame(tFeedback, 0, seq, Uint8List.fromList([pattern])));
  static Uint8List findBand(int seq, int seconds) => encode(Frame(tFindBand, 0, seq, Uint8List.fromList([seconds.clamp(1, 30).toInt()])));

  static Uint8List ack(int seq) => encode(Frame(tAck, 0, seq, Uint8List(0)));

  /// Construye el payload de salud (lo usa el simulador y los tests; el firmware hace lo mismo en C).
  static Uint8List healthPayload(HealthSample s) {
    final p = Uint8List(healthPayloadLen);
    final t = ((s.tempC ?? 0) * 100).round().clamp(0, 0xFFFF).toInt();
    final st = (s.steps ?? 0).clamp(0, 0xFFFFFFFF).toInt();
    p[0] = (s.hr ?? 0).clamp(0, 255).toInt();
    p[1] = (s.spo2 ?? 0).clamp(0, 100).toInt();
    p[2] = t & 0xFF;
    p[3] = (t >> 8) & 0xFF;
    p[4] = st & 0xFF;
    p[5] = (st >> 8) & 0xFF;
    p[6] = (st >> 16) & 0xFF;
    p[7] = (st >> 24) & 0xFF;
    p[8] = (s.battery ?? 0xFF).clamp(0, 255).toInt();
    return p;
  }

  /// null si el marco no es de salud o el payload es inválido. Valores fuera de rango fisiológico → null.
  static HealthSample? decodeHealth(Frame f) {
    if (f.type != tHealth || f.payload.length != healthPayloadLen) return null;
    final p = f.payload;
    final hr = p[0], spo2 = p[1], t = p[2] | (p[3] << 8);
    final steps = p[4] | (p[5] << 8) | (p[6] << 16) | (p[7] << 24);
    final bat = p[8];
    return HealthSample(
      hr: (hr >= 20 && hr <= 250) ? hr : null,
      spo2: (spo2 >= 50 && spo2 <= 100) ? spo2 : null,
      tempC: (t >= 3000 && t <= 4500) ? t / 100.0 : null,
      steps: steps,
      battery: bat <= 100 ? bat : null,
    );
  }

  static Uint8List config({required int sosHoldSeconds, bool fall = false, bool spray = false, bool haptic = true, int armSeconds = 5}) =>
      Uint8List.fromList([sosHoldSeconds.clamp(2, 5).toInt(), (fall ? cfgFall : 0) | (spray ? cfgSpray : 0) | (haptic ? cfgHaptic : 0), armSeconds.clamp(2, 10).toInt()]);

  static Uint8List command(int cmd, [int arg = 0]) => Uint8List.fromList([cmd, arg & 0xFF]);

  /// Hora para la pulsera (segundos UTC, u32 LE).
  static Uint8List timeSync(int epochSec) =>
      Uint8List.fromList([cmdTimeSync, 0, epochSec & 0xFF, (epochSec >> 8) & 0xFF, (epochSec >> 16) & 0xFF, (epochSec >> 24) & 0xFF]);
}
