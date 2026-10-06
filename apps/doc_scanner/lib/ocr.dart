import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'doc_store.dart';

/// On-device text recognition (Google ML Kit, Latin script). No internet.
class Ocr {
  Ocr._();

  static Future<PageText> readFile(String path) async {
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final r = await rec.processImage(InputImage.fromFilePath(path));
      final bytes = await File(path).readAsBytes();
      final dims = img.decodeImage(bytes);
      return PageText(dims?.width ?? 0, dims?.height ?? 0, [
        for (final b in r.blocks)
          for (final l in b.lines)
            OcrLine(l.text, Rect.fromLTRB(l.boundingBox.left,
                l.boundingBox.top, l.boundingBox.right, l.boundingBox.bottom)),
      ]);
    } finally {
      rec.close();
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
