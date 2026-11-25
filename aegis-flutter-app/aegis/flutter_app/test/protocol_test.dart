import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_app/ble/protocol.dart';
import 'package:aegis_app/health/reading.dart';

void main() {
  test('CRC-16/CCITT-FALSE de "123456789" es 0x29B1', () {
    expect(Proto.crc16('123456789'.codeUnits), 0x29B1);
  });

  test('encode/decode ida y vuelta', () {
    final f = Frame(Proto.tSosStart, 0, 513, Uint8List.fromList([1, 2, 3]));
    final d = Proto.decode(Proto.encode(f))!;
    expect([d.type, d.seq, d.payload.length], [Proto.tSosStart, 513, 3]);
  });

  test('marco con CRC dañado se descarta', () {
    final b = Proto.encode(Frame(Proto.tAck, 0, 1, Uint8List(0)));
    b[b.length - 1] ^= 0xFF;
    expect(Proto.decode(b), isNull);
  });

  test('salud: ida y vuelta por el protocolo', () {
    const s = HealthSample(hr: 88, spo2: 97, tempC: 36.62, steps: 70000, battery: 55);
    final f = Proto.decode(Proto.encode(Frame(Proto.tHealth, 0, 7, Proto.healthPayload(s))))!;
    final r = Proto.decodeHealth(f)!;
    expect([r.hr, r.spo2, r.steps, r.battery], [88, 97, 70000, 55]);
    expect(r.tempC, closeTo(36.62, 0.01));
  });

  test('salud: valores imposibles se descartan', () {
    final p = Proto.healthPayload(const HealthSample(hr: 5, spo2: 20, tempC: 10, steps: 1, battery: 50));
    final r = Proto.decodeHealth(Frame(Proto.tHealth, 0, 1, p))!;
    expect([r.hr, r.spo2, r.tempC], [null, null, null]);
  });

  test('alerta de FC: exige 3 lecturas seguidas y respeta el enfriamiento', () {
    final d = AnomalyDetector();
    expect(d.feed(170, 45, 150, 0), isNull);
    expect(d.feed(171, 45, 150, 2000), isNull);
    expect(d.feed(172, 45, 150, 4000), HrLevel.high);
    expect(d.feed(173, 45, 150, 6000), isNull); // enfriamiento
    expect(d.feed(70, 45, 150, 8000), isNull);
    expect(d.feed(30, 45, 150, 10000), isNull);
  });

  test('una lectura normal reinicia la racha', () {
    final d = AnomalyDetector();
    d.feed(170, 45, 150, 0);
    d.feed(170, 45, 150, 1000);
    d.feed(80, 45, 150, 2000);
    expect(d.feed(170, 45, 150, 3000), isNull);
  });

  test('v1.1: configuración y comandos con los límites correctos', () {
    expect(Proto.config(sosHoldSeconds: 9, fall: true, spray: false), [5, 1 | 4, 5]);
    expect(Proto.command(Proto.cmdFind, 300), [Proto.cmdFind, 300 & 0xFF]);
    final t = Proto.timeSync(0x01020304);
    expect(t.sublist(2), [4, 3, 2, 1]);
  });
}
