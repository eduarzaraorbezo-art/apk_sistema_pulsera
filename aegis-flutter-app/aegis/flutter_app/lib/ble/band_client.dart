import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'protocol.dart';

/// Cliente BLE de la pulsera. Solo habla BLE: no conoce la base de datos ni la API.
/// PENDIENTE: bonding con autenticación HMAC, reconexión por id guardado.
class BandClient {
  BandClient({required this.onFrame});
  final void Function(Frame) onFrame;

  final connected = StreamController<bool>.broadcast();
  bool isConnected = false;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmd;
  final _subs = <StreamSubscription>[];

  Future<void> start() async {
    if (_device != null) return;
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) return;
    final sub = FlutterBluePlus.onScanResults.listen((results) async {
      if (results.isEmpty || _device != null) return;
      _device = results.last.device;
      await FlutterBluePlus.stopScan();
      await _connect(_device!);
    });
    _subs.add(sub);
    await FlutterBluePlus.startScan(withServices: [Guid(Proto.svcControl)], timeout: const Duration(seconds: 30));
  }

  /// Reintenta la búsqueda (botón "Buscar pulsera").
  Future<void> rescan() async {
    if (isConnected) return;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _device = null;
    await start();
  }

  Future<void> _connect(BluetoothDevice d) async {
    _subs.add(d.connectionState.listen((s) async {
      isConnected = s == BluetoothConnectionState.connected;
      connected.add(isConnected);
      if (isConnected) await _setup(d);
    }));
    await d.connect(autoConnect: true, mtu: null); // autoConnect = reconexión automática
  }

  Future<void> _setup(BluetoothDevice d) async {
    try {
      await d.requestMtu(247);
      for (final s in await d.discoverServices()) {
        if (s.uuid != Guid(Proto.svcControl)) continue;
        for (final c in s.characteristics) {
          if (c.uuid == Guid(Proto.charCommand)) _cmd = c;
          if (c.uuid == Guid(Proto.charSosEvent) ||
              c.uuid == Guid(Proto.charCommandResp) ||
              c.uuid == Guid(Proto.charStatus)) {
            _subs.add(c.onValueReceived.listen((v) {
              final f = Proto.decode(v); // marcos con CRC o versión inválidos se descartan
              if (f != null) onFrame(f);
            }));
            await c.setNotifyValue(true); // indication / notify
          }
        }
      }
    } catch (_) {/* se reintenta al reconectar */}
  }

  Future<void> sendAck(int seq) async {
    try {
      await _cmd?.write(Proto.ack(seq));
    } catch (_) {}
  }

  int _seq = 0x8000; // las órdenes de la app usan números de secuencia altos para no chocar con los de la pulsera

  Future<void> _write(List<int> data) async {
    try {
      await _cmd?.write(data);
    } catch (_) {}
  }

  /// Vibración/LED de confirmación en la pulsera (p. ej. "mensaje enviado").
  Future<void> feedback(int pattern) => _write(Proto.feedback(_seq++ & 0xFFFF, pattern));

  /// Hace sonar/vibrar la pulsera para encontrarla.
  Future<void> findBand([int seconds = 10]) => _write(Proto.findBand(_seq++ & 0xFFFF, seconds));

  /// Envía un marco app→pulsera (configuración o comando). Falla en silencio si no hay conexión.
  Future<bool> send(int type, List<int> payload) async {
    try {
      if (_cmd == null) return false;
      await _cmd!.write(Proto.encode(Frame(type, 0, DateTime.now().millisecondsSinceEpoch & 0xFFFF, Uint8List.fromList(payload))));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _device?.disconnect();
    _device = null;
  }
}
