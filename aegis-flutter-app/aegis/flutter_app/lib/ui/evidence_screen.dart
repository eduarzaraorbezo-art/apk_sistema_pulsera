import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:uuid/uuid.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../sync/sync_service.dart';
import 'theme.dart';
import 'widgets.dart';

const _uuid = Uuid();
String _mb(num b) => '${(b / 1048576).toStringAsFixed(1)} MB';
String _t(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
const _trigName = {'sos': 'SOS', 'fall': 'Caída', 'tamper': 'Manipulación', 'manual': 'Manual', 'band': 'Pulsera', 'hr': 'Pulso'};

/// Evidencias guardadas en el servidor. Grabar audio automático o bajo demanda es Premium; las fotos, para todos.
class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key});
  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  Map<String, dynamic>? _data;
  bool _err = false;
  final _player = AudioPlayer();
  String? _playing;

  @override
  void initState() {
    super.initState();
    _load();
    _player.onPlayerComplete.listen((_) => mounted ? setState(() => _playing = null) : null);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Api.evidenceList();
    if (!mounted) return;
    setState(() { _data = r; _err = r == null; });
  }

  Future<void> _play(Map<String, dynamic> it) async {
    final id = it['id'] as String;
    if (_playing == id) {
      await _player.stop();
      setState(() => _playing = null);
      return;
    }
    final bytes = await Api.evidenceFile(id);
    if (bytes == null) {
      if (mounted) toast(context, 'No se pudo descargar.');
      return;
    }
    final f = File('${(await getTemporaryDirectory()).path}/ev_$id.m4a');
    await f.writeAsBytes(bytes, flush: true);
    await _player.play(DeviceFileSource(f.path));
    if (mounted) setState(() => _playing = id);
  }

  Future<void> _photo(AppState s) async {
    // Las fotos se adjuntan a la emergencia activa; con Premium también se puede crear una sesión nueva.
    String? session;
    final act = s.emergencies.where((e) => e['status'] == 'ACTIVE').toList();
    if (act.isNotEmpty) {
      session = act.first['id'] as String;
    } else if (s.canAutoRecord) {
      session = s.rec.session ?? _uuid.v4();
    } else {
      toast(context, 'Las fotos se adjuntan a una emergencia activa.');
      return;
    }
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 70);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final code = await Api.uploadEvidence(session, _uuid.v4(), 'photo', 'image/jpeg', bytes, sha256.convert(bytes).toString(), trigger: 'manual');
    if (!mounted) return;
    toast(context, code == 201 ? 'Foto guardada' : (code == 403 ? 'Límite de fotos de tu plan' : 'No se pudo subir la foto.'));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = Pal.of(context);
    final rec = s.rec;
    final items = ((_data?['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final used = (_data?['used_bytes'] as num?) ?? 0, quota = (_data?['quota_bytes'] as num?) ?? 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Evidencias')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card2(
            child: Column(children: [
              Icon(rec.active ? CupertinoIcons.mic_fill : CupertinoIcons.mic, size: 44, color: rec.active ? AC.red : AC.blue),
              const SizedBox(height: 6),
              Text(rec.active ? 'Grabando ${_t(rec.seconds)}' : 'Grabar audio de evidencia', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.label)),
              const SizedBox(height: 4),
              Text(rec.active ? 'Se guarda en trozos de 30 s y se sube en cuanto hay red.' : (s.canAutoRecord ? 'También se activa solo en un SOS, una caída o si manipulan la pulsera.' : 'Función Premium: grabación automática y audio.'),
                  textAlign: TextAlign.center, style: TextStyle(color: p.secondary, fontSize: 13)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: rec.active ? AC.red : AC.blue, minimumSize: const Size.fromHeight(48)),
                    icon: Icon(rec.active ? CupertinoIcons.stop_fill : CupertinoIcons.circle_fill),
                    label: Text(rec.active ? 'Detener' : 'Grabar'),
                    onPressed: () async {
                      final e = await s.toggleRecording();
                      if (!context.mounted) return;
                      if (e == 'premium') {
                        toast(context, 'Grabar evidencia es una función Premium.');
                      } else if (e != null) {
                        toast(context, e);
                      } else {
                        _load();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(onPressed: () => _photo(s), icon: const Icon(CupertinoIcons.camera_fill), label: const Text('Foto'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48))),
              ]),
              if (rec.planBlocked) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Tu plan no permite guardar audio en el servidor.', style: const TextStyle(color: AC.orange, fontSize: 12))),
              if (rec.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(rec.error!, style: const TextStyle(color: AC.red, fontSize: 12))),
            ]),
          ),
          if (_data != null) ...[
            const SectionLabel('Almacenamiento'),
            Card2(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LinearProgressIndicator(value: (used / quota).clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(6)),
                const SizedBox(height: 6),
                Text('${_mb(used)} de ${_mb(quota)} usados', style: TextStyle(color: p.secondary, fontSize: 13)),
              ]),
            ),
          ],
          const SectionLabel('Guardadas'),
          if (_data == null && !_err) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator.adaptive())),
          if (_err) Card2(child: Text('No se pudo cargar. Revisa tu conexión.', style: TextStyle(color: p.secondary))),
          if (_data != null && items.isEmpty) Card2(child: Text('Aún no hay evidencias.', style: TextStyle(color: p.secondary))),
          if (items.isNotEmpty)
            Group(children: [
              for (final it in items)
                Row2(
                  icon: it['kind'] == 'audio' ? (_playing == it['id'] ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill) : (it['kind'] == 'photo' ? CupertinoIcons.photo_fill : CupertinoIcons.videocam_fill),
                  color: it['kind'] == 'audio' ? AC.red : AC.teal,
                  title: '${it['kind'] == 'audio' ? 'Audio' : (it['kind'] == 'photo' ? 'Foto' : 'Video')}${it['duration_s'] == null ? '' : ' · ${_t(it['duration_s'] as int)}'}',
                  subtitle: '${_trigName[it['trigger']] ?? 'Manual'}${it['auto'] == true ? ' (automática)' : ''} · ${_mb(it['size'] as num)}${it['source'] == 'band' ? ' · pulsera' : ''}',
                  chevron: it['kind'] != 'audio',
                  trailing: IconButton(
                    icon: const Icon(CupertinoIcons.delete, color: AC.red, size: 20),
                    onPressed: () async {
                      await Api.deleteEvidence(it['id'] as String);
                      _load();
                    },
                  ),
                  onTap: it['kind'] == 'audio' ? () => _play(it) : null,
                ),
            ]),
          const SizedBox(height: 14),
          Text('Graba solo cuando tú o una emergencia lo activan, y hay un indicador rojo visible. Revisa la ley de tu país antes de grabar a otras personas.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.secondary)),
        ]),
      ),
    );
  }
}
