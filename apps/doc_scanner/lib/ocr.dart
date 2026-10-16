import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'doc_store.dart';

/// On-device text recognition (Google ML Kit, Latin script). No internet.
class Ocr {
  Ocr._();

  static Future<PageText> readFile(String path) async {
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final r = await rec.processImage(InputImage.fromFilePath(path));
      final (w, h) = await _size(await File(path).readAsBytes());
      return PageText(w, h, [
        for (final b in r.blocks)
          for (final l in b.lines)
            OcrLine(l.text, Rect.fromLTRB(l.boundingBox.left,
                l.boundingBox.top, l.boundingBox.right, l.boundingBox.bottom)),
      ]);
    } finally {
      rec.close();
    }
  }

  /// The image's pixel size from its header, without decoding it on the
  /// UI thread (a full decode froze the screen for seconds per page).
  static Future<(int, int)> _size(Uint8List bytes) async {
    try {
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      final d = await ui.ImageDescriptor.encoded(buf);
      final size = (d.width, d.height);
      d.dispose();
      buf.dispose();
      return size;
    } catch (_) {
      return (0, 0);
    }
  }

  /// Recognizes text in an image held in memory (e.g. a rendered PDF page).
  static Future<PageText> readBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File(
        '${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes);
    try {
      return await readFile(f.path);
    } finally {
      if (await f.exists()) await f.delete();
    }
  }
}
