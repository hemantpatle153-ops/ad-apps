import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'doc_store.dart';
import 'pdf_render.dart';

/// First-page preview of a saved PDF, rendered once and kept in memory.
class DocThumb extends StatelessWidget {
  const DocThumb({super.key, required this.doc, this.width = 48, this.height = 64});
  final SavedDoc doc;
  final double width;
  final double height;

  static final _cache = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> _render(SavedDoc d) =>
      _cache.putIfAbsent('${d.file.path}@${d.modified.millisecondsSinceEpoch}', () async {
        try {
          final bytes = await d.file.readAsBytes();
          return await PdfRender.page(bytes, 0, dpi: 30);
        } catch (_) {
          return null; // locked or damaged PDFs show an icon instead
        }
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        future: _render(doc),
        builder: (_, snap) {
          final png = snap.data;
          if (png != null) return Image.memory(png, fit: BoxFit.cover, gaplessPlayback: true);
          return Icon(
            snap.connectionState == ConnectionState.done ? Icons.picture_as_pdf : Icons.description_outlined,
            color: scheme.primary,
          );
        },
      ),
    );
  }
}
