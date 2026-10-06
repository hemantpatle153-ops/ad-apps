import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../jobs.dart';
import '../pdf_render.dart';
import '../ui_helpers.dart';

/// What to put on the page.
sealed class Placement {
  const Placement();
}

/// An image (signature, stamp) the user drags and resizes.
class ImagePlacement extends Placement {
  const ImagePlacement(this.png, this.aspect);
  final Uint8List png;
  final double aspect; // width / height
}

/// A line of text the user drags into place.
class TextPlacement extends Placement {
  const TextPlacement(this.text, this.fontSize, this.color);
  final String text;
  final double fontSize; // points
  final Color color;
}

/// Black boxes the user draws over private details.
class RedactPlacement extends Placement {
  const RedactPlacement();
}

class PlaceResult {
  const PlaceResult(this.page, this.box, this.boxes);
  final int page;

  /// Fractional box of the image or the text's top-left (image/text).
  final Rect box;

  /// Page index to fractional boxes (redact).
  final Map<int, List<Rect>> boxes;
}

/// Shows the PDF's pages so the user can place a signature, text or
/// redaction boxes exactly where they want them.
class PlaceScreen extends StatefulWidget {
  const PlaceScreen({super.key, required this.pdf, required this.what, required this.title});
  final Uint8List pdf;
  final Placement what;
  final String title;

  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  int _count = 0;
  int _page = 0;
  Uint8List? _png;
  double _ptsW = 595, _ptsH = 842;
  // Image/text box in page fractions.
  Offset _pos = const Offset(0.55, 0.8);
  double _width = 0.3; // fraction of page width (images)
  final Map<int, List<Rect>> _boxes = {};
  Offset? _dragStart;
  Rect? _drawing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _count = await bg(pageCountJob, widget.pdf);
    if (widget.what is TextPlacement) _pos = const Offset(0.1, 0.1);
    await _show(0);
  }

  Future<void> _show(int page) async {
    setState(() {
      _page = page;
      _png = null;
    });
    final (png, w, h) = await PdfRender.pageWithSize(widget.pdf, page);
    if (!mounted) return;
    setState(() {
      _png = png;
      _ptsW = w;
      _ptsH = h;
    });
  }

  Rect get _imageBox {
    final w = widget.what;
    if (w is ImagePlacement) {
      final hFrac = _width * _ptsW / w.aspect / _ptsH;
      return Rect.fromLTWH(_pos.dx, _pos.dy, _width, hFrac);
    }
    return Rect.fromLTWH(_pos.dx, _pos.dy, 0, 0);
  }

  void _done() {
    Navigator.pop(context, PlaceResult(_page, _imageBox, _boxes));
  }

  Widget _overlay(Size area) {
    final w = widget.what;
    final scale = area.width / _ptsW; // screen px per point
    switch (w) {
      case ImagePlacement():
        final b = _imageBox;
        return Positioned(
          left: b.left * area.width,
          top: b.top * area.height,
          width: b.width * area.width,
          height: b.height * area.height,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() => _pos = Offset(
                (_pos.dx + d.delta.dx / area.width).clamp(0, 1 - b.width),
                (_pos.dy + d.delta.dy / area.height).clamp(0, 1 - b.height))),
            child: DecoratedBox(
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue, width: 1.5)),
              child: Image.memory(w.png, fit: BoxFit.fill),
            ),
          ),
        );
      case TextPlacement():
        return Positioned(
          left: _pos.dx * area.width,
          top: _pos.dy * area.height,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() => _pos = Offset(
                (_pos.dx + d.delta.dx / area.width).clamp(0, 0.98),
                (_pos.dy + d.delta.dy / area.height).clamp(0, 0.98))),
            child: Container(
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue, width: 1)),
              padding: const EdgeInsets.all(1),
              child: Text(w.text,
                  style: TextStyle(
                      fontSize: w.fontSize * scale,
                      color: w.color,
                      height: 1.15)),
            ),
          ),
        );
      case RedactPlacement():
        final boxes = [...?_boxes[_page], if (_drawing != null) _drawing!];
        return Positioned.fill(
          child: GestureDetector(
            onPanStart: (d) => _dragStart = Offset(
                d.localPosition.dx / area.width, d.localPosition.dy / area.height),
            onPanUpdate: (d) {
              final s = _dragStart;
              if (s == null) return;
              final p = Offset(
                  (d.localPosition.dx / area.width).clamp(0, 1),
                  (d.localPosition.dy / area.height).clamp(0, 1));
              setState(() => _drawing = Rect.fromPoints(s, p));
            },
            onPanEnd: (_) => setState(() {
              final r = _drawing;
              if (r != null && r.width > 0.005 && r.height > 0.005) {
                (_boxes[_page] ??= []).add(r);
              }
              _drawing = null;
              _dragStart = null;
            }),
            child: Stack(children: [
              for (final r in boxes)
                Positioned(
                  left: r.left * area.width,
                  top: r.top * area.height,
                  width: r.width * area.width,
                  height: r.height * area.height,
                  child: const ColoredBox(color: Colors.black),
                ),
            ]),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final redact = widget.what is RedactPlacement;
    final total = _boxes.values.fold<int>(0, (n, l) => n + l.length);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (redact)
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: (_boxes[_page]?.isEmpty ?? true)
                  ? null
                  : () => setState(() => _boxes[_page]!.removeLast()),
            ),
          TextButton(
            onPressed: _png == null || (redact && total == 0) ? null : _done,
            child: const Text('Apply'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              redact
                  ? 'Drag over anything you want hidden. Redacted pages become images, so the hidden text is removed for good.'
                  : 'Drag to move it. Pick the page below.',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: _png == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: AspectRatio(
                      aspectRatio: _ptsW / _ptsH,
                      child: LayoutBuilder(
                        builder: (_, c) => Stack(children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(boxShadow: kElevationToShadow[2]),
                              child: Image.memory(_png!, fit: BoxFit.fill),
                            ),
                          ),
                          _overlay(c.biggest),
                        ]),
                      ),
                    ),
                  ),
          ),
          if (widget.what is ImagePlacement)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Text('Size'),
                Expanded(
                  child: Slider(
                    value: _width,
                    min: 0.1,
                    max: 0.9,
                    onChanged: (v) => setState(() {
                      _width = v;
                      _pos = Offset(_pos.dx.clamp(0, 1 - v), _pos.dy.clamp(0, 0.95));
                    }),
                  ),
                ),
              ]),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _page > 0 ? () => _show(_page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${_page + 1} of $_count'),
              IconButton(
                onPressed: _page < _count - 1 ? () => _show(_page + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
