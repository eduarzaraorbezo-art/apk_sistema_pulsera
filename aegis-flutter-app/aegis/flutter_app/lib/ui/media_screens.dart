import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../sync/sync_service.dart';
import 'theme.dart';
import 'widgets.dart';

/// Caché en memoria de archivos descargados (miniaturas y visor).
class MediaCache {
  static final _m = <String, Uint8List>{};
  static final _order = <String>[];

  static Future<Uint8List?> get(String id) async {
    final hit = _m[id];
    if (hit != null) return hit;
    final b = await Api.evidenceFile(id);
    if (b == null) return null;
    final u = Uint8List.fromList(b);
    _m[id] = u;
    _order.add(id);
    if (_order.length > 30) _m.remove(_order.removeAt(0));
    return u;
  }
}

/// Miniatura cuadrada de una foto guardada.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: MediaCache.get(id),
        builder: (c, snap) {
          final b = snap.data;
          if (b != null) return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 360);
          return Center(child: snap.connectionState == ConnectionState.done ? const Icon(CupertinoIcons.photo, color: AC.gray) : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
        },
      );
}

/// Visor de fotos a pantalla completa: desliza para cambiar, pellizca para ampliar.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.ids, required this.initial});
  final List<String> ids;
  final int initial;
  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text('${_i + 1} / ${widget.ids.length}', style: const TextStyle(color: Colors.white))),
        body: PageView.builder(
          controller: _pc,
          itemCount: widget.ids.length,
          onPageChanged: (v) => setState(() => _i = v),
          itemBuilder: (c, i) => FutureBuilder<Uint8List?>(
            future: MediaCache.get(widget.ids[i]),
            builder: (c, snap) {
              final b = snap.data;
              if (b == null) {
                return Center(child: snap.connectionState == ConnectionState.done ? const Text('No se pudo cargar la foto', style: TextStyle(color: Colors.white70)) : const CircularProgressIndicator.adaptive());
              }
              return InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: Image.memory(b, fit: BoxFit.contain)));
            },
          ),
        ),
      );
}

/// Reproductor de video de una evidencia guardada.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.id});
  final String id;
  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _c;
  String? _err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final b = await MediaCache.get(widget.id);
      if (b == null) throw 'No se pudo descargar el video';
      final f = File('${(await getTemporaryDirectory()).path}/ev_${widget.id}.mp4');
      await f.writeAsBytes(b, flush: true);
      final c = VideoPlayerController.file(f);
      await c.initialize();
      c.addListener(() { if (mounted) setState(() {}); });
      await c.play();
      if (!mounted) { await c.dispose(); return; }
      setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Video', style: TextStyle(color: Colors.white))),
      body: _err != null
          ? Center(child: Text(_err!, style: const TextStyle(color: Colors.white70)))
          : c == null
              ? const Center(child: CircularProgressIndicator.adaptive())
              : Column(children: [
                  Expanded(child: Center(child: AspectRatio(aspectRatio: c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio, child: VideoPlayer(c)))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    child: Row(children: [
                      IconButton(
                        iconSize: 34, color: Colors.white,
                        icon: Icon(c.value.isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill),
                        onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
                      ),
                      Text(_fmt(c.value.position), style: const TextStyle(color: Colors.white70)),
                      Expanded(
                        child: Slider(
                          value: c.value.position.inMilliseconds.clamp(0, c.value.duration.inMilliseconds == 0 ? 1 : c.value.duration.inMilliseconds).toDouble(),
                          max: (c.value.duration.inMilliseconds == 0 ? 1 : c.value.duration.inMilliseconds).toDouble(),
                          onChanged: (v) => c.seekTo(Duration(milliseconds: v.toInt())),
                        ),
                      ),
                      Text(_fmt(c.value.duration), style: const TextStyle(color: Colors.white70)),
                    ]),
                  ),
                ]),
    );
  }
}

/// Graba un video corto con la cámara y lo sube como evidencia (máx. 30 s por clip).
class VideoRecordScreen extends StatefulWidget {
  const VideoRecordScreen({super.key, required this.session, this.trigger = 'manual', this.auto = false});
  final String session, trigger;
  final bool auto;
  @override
  State<VideoRecordScreen> createState() => _VideoRecordScreenState();
}

class _VideoRecordScreenState extends State<VideoRecordScreen> {
  static const _maxSec = 30;
  CameraController? _c;
  List<CameraDescription> _cams = const [];
  int _cam = 0;
  bool _rec = false, _busy = false;
  int _sec = 0;
  String? _err;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) throw 'Este dispositivo no tiene cámara';
      _cam = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_cam < 0) _cam = 0;
      await _start();
    } catch (e) {
      if (mounted) setState(() => _err = 'No se pudo abrir la cámara: $e');
    }
  }

  Future<void> _start() async {
    await _c?.dispose();
    final c = CameraController(_cams[_cam], ResolutionPreset.medium, enableAudio: true);
    _c = c;
    await c.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final c = _c;
    if (c == null || !c.value.isInitialized || _busy) return;
    if (!_rec) {
      await c.startVideoRecording();
      _sec = 0;
      _t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _sec++);
        if (_sec >= _maxSec) _toggle();
      });
      setState(() => _rec = true);
    } else {
      _t?.cancel();
      setState(() { _rec = false; _busy = true; });
      try {
        final x = await c.stopVideoRecording();
        final bytes = await x.readAsBytes();
        final code = await Api.uploadEvidence(widget.session, const Uuid().v4(), 'video', 'video/mp4', bytes, sha256.convert(bytes).toString(),
            trigger: widget.trigger, auto: widget.auto, durationS: _sec);
        if (!mounted) return;
        toast(context, switch (code) {
          201 => 'Video guardado',
          403 => 'Tu plan o tu almacenamiento no permite guardar este video',
          413 => 'El video pesa demasiado',
          _ => 'No se pudo subir el video. Inténtalo con mejor conexión.',
        });
        if (code == 201) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) toast(context, 'Error al guardar el video');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Grabar video', style: TextStyle(color: Colors.white))),
      body: _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70))))
          : (c == null || !c.value.isInitialized)
              ? const Center(child: CircularProgressIndicator.adaptive())
              : Stack(children: [
                  Positioned.fill(child: Center(child: CameraPreview(c))),
                  Positioned(
                    top: 12, left: 0, right: 0,
                    child: Center(
                      child: Pill(_rec ? 'REC  00:${_sec.toString().padLeft(2, '0')} / 00:$_maxSec' : 'Máx. $_maxSec s por clip', icon: _rec ? CupertinoIcons.circle_fill : CupertinoIcons.videocam_fill, color: _rec ? AC.red : AC.gray, filled: _rec),
                    ),
                  ),
                  Positioned(
                    bottom: 36, left: 0, right: 0,
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      const SizedBox(width: 56),
                      GestureDetector(
                        onTap: _toggle,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 78, height: 78,
                          padding: EdgeInsets.all(_rec ? 24 : 6),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                          child: Container(decoration: BoxDecoration(color: AC.red, borderRadius: BorderRadius.circular(_rec ? 6 : 40))),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: (_cams.length > 1 && !_rec && !_busy)
                            ? IconButton(
                                iconSize: 30, color: Colors.white, icon: const Icon(CupertinoIcons.camera_rotate_fill),
                                onPressed: () async { _cam = (_cam + 1) % _cams.length; await _start(); },
                              )
                            : null,
                      ),
                    ]),
                  ),
                  if (_busy) Positioned.fill(child: Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator.adaptive()))),
                ]),
    );
  }
}
