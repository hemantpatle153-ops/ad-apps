import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ui_helpers.dart';
import 'capture.dart';
import 'geometry.dart';

/// What the camera is for. Documents get edge detection and auto-crop;
/// photos are kept whole.
enum ScanMode { document, photo }

/// The app's own document camera: live page outline, auto-capture when the
/// page is steady, flash, tap to focus, batch pages. Runs entirely in the
/// app, with no Google Play services scanner.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({
    super.key,
    this.mode = ScanMode.document,
    this.pageLimit = 50,
    this.title,
  });

  final ScanMode mode;
  final int pageLimit;
  final String? title;

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

enum _Problem { none, denied, deniedForever, noCamera, failed }

class _CameraScanScreenState extends State<CameraScanScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cam;
  _Problem _problem = _Problem.none;
  String _error = '';
  late ScanMode _mode = widget.mode;
  bool _auto = true;
  bool _grid = false;
  FlashMode _flash = FlashMode.off;

  // Live detection.
  Quad? _live; // in portrait preview coordinates
  Quad? _shown; // smoothed for drawing
  int _steady = 0;
  bool _detecting = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  // Captured pages.
  final _pages = <String>[];
  int _processing = 0;
  bool _shooting = false;
  late final AnimationController _flashFx =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Offset? _focusAt;

  static const _steadyFrames = 5; // ~1.5 s at the detection rate
  static const _frameGap = Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([]);
    _flashFx.dispose();
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _cam;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cam = null;
      cam?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && cam == null) {
      _start();
    }
  }

  Future<void> _start() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _problem =
          status.isPermanentlyDenied ? _Problem.deniedForever : _Problem.denied);
      return;
    }
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _problem = _Problem.noCamera);
        return;
      }
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final cam = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await cam.initialize();
      await cam.setFlashMode(_flash).catchError((_) {});
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _problem = _Problem.none;
      });
      await _startStream();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = e.code.contains('Access') ? _Problem.denied : _Problem.failed;
        _error = e.description ?? e.code;
      });
    }
  }

  Future<void> _startStream() async {
    final cam = _cam;
    if (cam == null || _mode != ScanMode.document || cam.value.isStreamingImages) return;
    try {
      await cam.startImageStream(_onFrame);
    } catch (_) {
      // Some phones can't stream at this size; capture still works.
    }
  }

  Future<void> _stopStream() async {
    final cam = _cam;
    if (cam != null && cam.value.isStreamingImages) {
      try {
        await cam.stopImageStream();
      } catch (_) {}
    }
  }

  void _onFrame(CameraImage frame) {
    final now = DateTime.now();
    if (_detecting || _shooting || now.difference(_lastFrame) < _frameGap) return;
    _detecting = true;
    _lastFrame = now;
    final plane = frame.planes.first;
    final luma = sampleLuma(plane.bytes, frame.width, frame.height, plane.bytesPerRow);
    final turns = (_cam?.description.sensorOrientation ?? 90) ~/ 90;
    bg(detectFrameJob, luma).then((q) {
      if (!mounted) return;
      final portrait = q?.rotated(turns);
      setState(() {
        if (portrait == null) {
          _steady = 0;
          _live = null;
        } else {
          final prev = _live;
          _steady = prev != null && prev.maxShift(portrait) < 0.025 ? _steady + 1 : 0;
          _live = portrait;
        }
        final target = _live;
        _shown = target == null
            ? null
            : (_shown == null ? target : _shown!.lerp(target, 0.6));
      });
      if (_auto && _steady >= _steadyFrames && !_shooting) _shoot();
    }).whenComplete(() => _detecting = false);
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (cam == null || _shooting || _pages.length >= widget.pageLimit) return;
    setState(() => _shooting = true);
    HapticFeedback.mediumImpact();
    final hint = _live;
    try {
      await _stopStream();
      final shot = await cam.takePicture();
      _flashFx.forward(from: 0);
      _steady = 0;
      _process(shot, hint);
    } catch (e) {
      if (mounted) toast(context, 'Could not take the picture: $e');
    } finally {
      if (mounted) {
        setState(() => _shooting = false);
        if (_pages.length + _processing < widget.pageLimit) await _startStream();
      }
    }
  }

  Future<void> _process(XFile shot, Quad? hint) async {
    setState(() => _processing++);
    try {
      final bytes = await shot.readAsBytes();
      final dir = await getApplicationDocumentsDirectory();
      final pages = Directory('${dir.path}/scans');
      if (!await pages.exists()) await pages.create(recursive: true);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final original = File('${pages.path}/orig_$stamp.jpg');
      await original.writeAsBytes(bytes, flush: true);
      final res = await bg(processCapture, (bytes, hint, _mode == ScanMode.document));
      final cropped = File('${pages.path}/page_$stamp.jpg');
      await cropped.writeAsBytes(res.jpeg, flush: true);
      pageSources[cropped.path] = PageSource(original.path, res.quad);
      if (!mounted) return;
      setState(() => _pages.add(cropped.path));
      if (_pages.length >= widget.pageLimit) _finish();
    } catch (e) {
      if (mounted) toast(context, 'Could not process the page: $e');
    } finally {
      if (mounted) setState(() => _processing--);
    }
  }

  Future<void> _import() async {
    await _stopStream();
    final picked = [for (final f in await ImagePicker().pickMultiImage()) f.path];
    if (!mounted) return;
    for (final p in picked) {
      if (_pages.length + _processing >= widget.pageLimit) break;
      await _process(XFile(p), null);
    }
    await _startStream();
  }

  void _finish() {
    if (_processing > 0) {
      toast(context, 'Finishing the last page…');
      return;
    }
    Navigator.pop(context, List<String>.of(_pages));
  }

  Future<void> _tapFocus(TapUpDetails d, BoxConstraints c) async {
    final cam = _cam;
    if (cam == null) return;
    final p = Offset(d.localPosition.dx / c.maxWidth, d.localPosition.dy / c.maxHeight);
    setState(() => _focusAt = d.localPosition);
    try {
      await cam.setFocusPoint(p);
      await cam.setExposurePoint(p);
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusAt = null);
    });
  }

  Future<void> _cycleFlash() async {
    const order = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
    final next = order[(order.indexOf(_flash) + 1) % order.length];
    try {
      await _cam?.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {
      if (mounted) toast(context, "This camera's flash can't be changed.");
    }
  }

  Future<bool> _confirmLeave() async {
    if (_pages.isEmpty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Discard ${_pages.length} page${_pages.length == 1 ? '' : 's'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep scanning')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
        ],
      ),
    );
    return r == true;
  }

  String get _hint {
    if (_pages.length >= widget.pageLimit) return 'Page limit reached';
    if (_mode == ScanMode.photo) return 'Tap the button to take a photo';
    if (_shooting) return 'Capturing…';
    if (_live == null) return 'Point the camera at a document';
    if (_auto) return _steady > 1 ? 'Hold steady…' : 'Document found';
    return 'Document found. Tap to capture';
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    return PopScope(
      canPop: _pages.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context, <String>[]);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            _topBar(),
            Expanded(
              child: _problem != _Problem.none
                  ? _ProblemView(
                      problem: _problem,
                      error: _error,
                      onRetry: _start,
                      onGallery: _import,
                    )
                  : cam == null || !cam.value.isInitialized
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : Center(
                          child: AspectRatio(
                            aspectRatio: 1 / cam.value.aspectRatio,
                            child: LayoutBuilder(
                              builder: (_, c) => GestureDetector(
                                onTapUp: (d) => _tapFocus(d, c),
                                child: Stack(fit: StackFit.expand, children: [
                                  CameraPreview(cam),
                                  if (_grid) const CustomPaint(painter: _GridPainter()),
                                  if (_mode == ScanMode.document)
                                    AnimatedOpacity(
                                      opacity: _shown == null ? 0 : 1,
                                      duration: const Duration(milliseconds: 200),
                                      child: CustomPaint(
                                        painter: _QuadPainter(
                                          _shown,
                                          steady: _auto ? (_steady / _steadyFrames).clamp(0, 1) : 0,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  if (_focusAt != null)
                                    Positioned(
                                      left: _focusAt!.dx - 30,
                                      top: _focusAt!.dy - 30,
                                      child: Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.amber, width: 1.5),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  FadeTransition(
                                    opacity: Tween(begin: 0.8, end: 0.0).animate(_flashFx),
                                    child: IgnorePointer(
                                      child: AnimatedBuilder(
                                        animation: _flashFx,
                                        builder: (_, child) => ColoredBox(
                                          color: _flashFx.isAnimating ? Colors.white : Colors.transparent,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 16,
                                    child: Center(child: _HintPill(text: _hint)),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        ),
            ),
            _bottomBar(),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() {
    final flashIcon = switch (_flash) {
      FlashMode.off => Icons.flash_off,
      FlashMode.auto => Icons.flash_auto,
      FlashMode.always => Icons.flash_on,
      FlashMode.torch => Icons.highlight,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        IconButton(
          tooltip: 'Close',
          color: Colors.white,
          icon: const Icon(Icons.close),
          onPressed: () async {
            if (await _confirmLeave() && mounted) Navigator.of(context).pop(<String>[]);
          },
        ),
        Expanded(
          child: Text(widget.title ?? (_mode == ScanMode.document ? 'Scan document' : 'Take photo'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        IconButton(
            tooltip: 'Flash', color: Colors.white, icon: Icon(flashIcon), onPressed: _cycleFlash),
        IconButton(
          tooltip: 'Grid',
          color: _grid ? Colors.amber : Colors.white,
          icon: const Icon(Icons.grid_3x3),
          onPressed: () => setState(() => _grid = !_grid),
        ),
      ]),
    );
  }

  Widget _bottomBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Chip(
            label: 'Document',
            selected: _mode == ScanMode.document,
            onTap: () async {
              setState(() => _mode = ScanMode.document);
              await _startStream();
            },
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Photo',
            selected: _mode == ScanMode.photo,
            onTap: () async {
              await _stopStream();
              setState(() {
                _mode = ScanMode.photo;
                _live = _shown = null;
              });
            },
          ),
          if (_mode == ScanMode.document) ...[
            const SizedBox(width: 16),
            _Chip(
              label: _auto ? 'Auto capture' : 'Manual',
              icon: _auto ? Icons.auto_awesome : Icons.touch_app_outlined,
              selected: _auto,
              onTap: () => setState(() {
                _auto = !_auto;
                _steady = 0;
              }),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Import from gallery',
                iconSize: 30,
                color: Colors.white,
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: _import,
              ),
            ),
          ),
          GestureDetector(
            onTap: _cam == null ? null : _shoot,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              padding: const EdgeInsets.all(5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _shooting ? Colors.white54 : Colors.white,
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _pages.isEmpty && _processing == 0
                  ? const SizedBox(width: 56)
                  : GestureDetector(
                      onTap: _finish,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Container(
                          width: 52,
                          height: 66,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(6),
                            color: Colors.white10,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _pages.isEmpty
                              ? const Center(
                                  child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                              : Image.file(File(_pages.last), fit: BoxFit.cover, cacheWidth: 120),
                        ),
                        Positioned(
                          right: -8,
                          top: -8,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: scheme.primary,
                            child: Text('${_pages.length + _processing}',
                                style: TextStyle(fontSize: 12, color: scheme.onPrimary)),
                          ),
                        ),
                      ]),
                    ),
            ),
          ),
        ]),
        if (_pages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: selected ? Colors.black : Colors.white),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.quad, {required this.steady, required this.color});
  final Quad? quad;
  final double steady;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final path = Path()
      ..moveTo(q.tl.x * size.width, q.tl.y * size.height)
      ..lineTo(q.tr.x * size.width, q.tr.y * size.height)
      ..lineTo(q.br.x * size.width, q.br.y * size.height)
      ..lineTo(q.bl.x * size.width, q.bl.y * size.height)
      ..close();
    final c = Color.lerp(color, Colors.greenAccent, steady)!;
    canvas.drawPath(path, Paint()..color = c.withValues(alpha: 0.18));
    canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round);
    for (final p in q.points) {
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), 7, Paint()..color = c);
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), 3.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.quad != quad || old.steady != steady;
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), p);
      canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProblemView extends StatelessWidget {
  const _ProblemView(
      {required this.problem, required this.error, required this.onRetry, required this.onGallery});
  final _Problem problem;
  final String error;
  final VoidCallback onRetry;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (problem) {
      _Problem.denied => (
          'Camera permission needed',
          'Doc Scanner uses the camera only to scan your documents. Photos stay on your phone.'
        ),
      _Problem.deniedForever => (
          'Turn on camera access',
          'Camera access is off for Doc Scanner. Open Settings, tap Permissions, and allow Camera.'
        ),
      _Problem.noCamera => ('No camera found', 'This device has no camera. You can still import photos.'),
      _ => ('Camera could not start', 'Close other camera apps and try again. ($error)'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 64),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          if (problem == _Problem.deniedForever)
            FilledButton(onPressed: openAppSettings, child: const Text('Open settings'))
          else if (problem != _Problem.noCamera)
            FilledButton(onPressed: onRetry, child: const Text('Allow camera')),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onGallery,
            child: const Text('Import from gallery instead', style: TextStyle(color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}
