import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draw a signature with a finger. Returns a transparent PNG and its
/// aspect ratio, trimmed to the ink.
class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final _strokes = <List<Offset>>[];
  Color _color = const Color(0xFF0D47A1);

  Future<void> _done() async {
    final pts = _strokes.expand((s) => s).toList();
    if (pts.isEmpty) return;
    var bounds = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      bounds = bounds.expandToInclude(Rect.fromCenter(center: p, width: 1, height: 1));
    }
    bounds = bounds.inflate(8);
    const scale = 3.0; // sharper when printed
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    _SigPainter(_strokes, _color).paint(canvas, bounds.size);
    final image = await rec.endRecording().toImage(
        (bounds.width * scale).ceil(), (bounds.height * scale).ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || data == null) return;
    Navigator.pop<(Uint8List, double)>(
        context, (data.buffer.asUint8List(), bounds.width / bounds.height));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw your signature'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(_strokes.clear),
          ),
          TextButton(
              onPressed: _strokes.isEmpty ? null : _done,
              child: const Text('Use')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRect(
                child: GestureDetector(
                  onPanStart: (d) =>
                      setState(() => _strokes.add([d.localPosition])),
                  onPanUpdate: (d) =>
                      setState(() => _strokes.last.add(d.localPosition)),
                  child: CustomPaint(
                    painter: _SigPainter(_strokes, _color),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final c in const [Color(0xFF0D47A1), Colors.black, Color(0xFFB71C1C)])
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InkWell(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      backgroundColor: c,
                      radius: 16,
                      child: _color == c
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SigPainter extends CustomPainter {
  _SigPainter(this.strokes, this.color);
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
