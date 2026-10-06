import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../ui_helpers.dart';
import 'capture.dart';
import 'geometry.dart';

/// Drag the four corners onto the page's edges; a magnifier shows the
/// corner under your finger. Returns the new cropped page path.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.pagePath});

  /// The current (cropped) page; its original photo is used when known.
  final String pagePath;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late final PageSource? _source = pageSources[widget.pagePath];
  late String _imagePath = _source?.original ?? widget.pagePath;
  Uint8List? _bytes;
  ui.Image? _image;
  late Quad _quad = _source?.quad ?? Quad.inset;
  int? _dragging;
  Offset? _finger;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await File(_imagePath).readAsBytes();
    // Show the photo upright (EXIF applied), the same way it's cropped.
    final upright = await bg(processCapture, (raw, null, false));
    final codec = await ui.instantiateImageCodec(upright.jpeg);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _bytes = upright.jpeg;
      _image = frame.image;
    });
    if (_source == null) _auto(quiet: true);
  }

  Future<void> _auto({bool quiet = false}) async {
    final b = _bytes;
    if (b == null) return;
    final q = await bg(detectPhotoJob, b);
    if (!mounted) return;
    if (q == null) {
      if (!quiet) toast(context, "Couldn't find the page edges. Drag the corners.");
      return;
    }
    setState(() => _quad = q);
  }

  Future<void> _apply() async {
    final b = _bytes;
    if (b == null) return;
    setState(() => _busy = true);
    try {
      final out = await bg(recropJob, (b, _quad));
      final dir = await getApplicationDocumentsDirectory();
      final pages = Directory('${dir.path}/scans');
      if (!await pages.exists()) await pages.create(recursive: true);
      final f = File('${pages.path}/page_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await f.writeAsBytes(out, flush: true);
      // Keep the upright original so the next crop starts from it.
      final orig = File('${pages.path}/orig_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await orig.writeAsBytes(b, flush: true);
      pageSources[f.path] = PageSource(orig.path, _quad);
      _imagePath = orig.path;
      if (mounted) Navigator.pop(context, f.path);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Crop'),
        actions: [
          TextButton(
            onPressed: image == null || _busy || !_quad.isConvex ? null : _apply,
            child: const Text('Apply'),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: image == null || _busy
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: image.width / image.height,
                      child: LayoutBuilder(builder: (_, c) {
                        final size = c.biggest;
                        Offset px(P p) => Offset(p.x * size.width, p.y * size.height);
                        return GestureDetector(
                          onPanStart: (d) {
                            var best = 0;
                            var bestD = double.infinity;
                            for (var i = 0; i < 4; i++) {
                              final dd = (px(_quad.points[i]) - d.localPosition).distance;
                              if (dd < bestD) {
                                bestD = dd;
                                best = i;
                              }
                            }
                            if (bestD < 60) {
                              setState(() {
                                _dragging = best;
                                _finger = d.localPosition;
                              });
                            }
                          },
                          onPanUpdate: (d) {
                            final i = _dragging;
                            if (i == null) return;
                            final p = d.localPosition;
                            setState(() {
                              _finger = p;
                              _quad = _quad.withPoint(
                                  i, P(p.dx / size.width, p.dy / size.height).clamp());
                            });
                          },
                          onPanEnd: (_) => setState(() {
                            _dragging = null;
                            _finger = null;
                          }),
                          child: Stack(clipBehavior: Clip.none, children: [
                            Positioned.fill(child: RawImage(image: image, fit: BoxFit.fill)),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CropPainter(_quad, scheme.primary,
                                    valid: _quad.isConvex, active: _dragging),
                              ),
                            ),
                            if (_dragging != null && _finger != null)
                              _Loupe(
                                image: image,
                                at: px(_quad.points[_dragging!]),
                                area: size,
                                color: scheme.primary,
                              ),
                          ]),
                        );
                      }),
                    ),
                  ),
                ),
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _Action(icon: Icons.auto_fix_high, label: 'Auto', onTap: () => _auto()),
            _Action(
                icon: Icons.fullscreen,
                label: 'Full page',
                onTap: () => setState(() => _quad = Quad.full)),
            _Action(
                icon: Icons.restart_alt,
                label: 'Reset',
                onTap: () => setState(() => _quad = _source?.quad ?? Quad.inset)),
          ]),
        ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.q, this.color, {required this.valid, this.active});
  final Quad q;
  final Color color;
  final bool valid;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(P p) => Offset(p.x * size.width, p.y * size.height);
    final path = Path()..addPolygon([for (final p in q.points) px(p)], true);
    // Dim everything outside the page.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(path, Offset.zero);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    final c = valid ? color : Colors.redAccent;
    canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    for (var i = 0; i < 4; i++) {
      final o = px(q.points[i]);
      canvas.drawCircle(o, i == active ? 16 : 12, Paint()..color = c.withValues(alpha: 0.35));
      canvas.drawCircle(o, 7, Paint()..color = c);
      canvas.drawCircle(o, 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.q != q || old.active != active || old.valid != valid;
}

/// A round magnifier above the finger showing the corner up close.
class _Loupe extends StatelessWidget {
  const _Loupe({required this.image, required this.at, required this.area, required this.color});
  final ui.Image image;
  final Offset at;
  final Size area;
  final Color color;

  static const _size = 110.0;
  static const _zoom = 2.5;

  @override
  Widget build(BuildContext context) {
    // Sit above the finger, or below it near the top edge.
    final top = at.dy - _size - 40 < -20 ? at.dy + 40 : at.dy - _size - 40;
    return Positioned(
      left: (at.dx - _size / 2).clamp(-20.0, area.width - _size + 20),
      top: top,
      child: IgnorePointer(
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: kElevationToShadow[4],
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(painter: _LoupePainter(image, at, area, color)),
        ),
      ),
    );
  }
}

class _LoupePainter extends CustomPainter {
  _LoupePainter(this.image, this.at, this.area, this.color);
  final ui.Image image;
  final Offset at;
  final Size area;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = image.width / area.width, sy = image.height / area.height;
    final half = size.width / 2 / _Loupe._zoom;
    final src = Rect.fromCenter(
        center: Offset(at.dx * sx, at.dy * sy), width: half * 2 * sx, height: half * 2 * sy);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    canvas.drawImageRect(image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawLine(c - const Offset(12, 0), c + const Offset(12, 0), p);
    canvas.drawLine(c - const Offset(0, 12), c + const Offset(0, 12), p);
  }

  @override
  bool shouldRepaint(_LoupePainter old) => old.at != at;
}
