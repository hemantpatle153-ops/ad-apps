import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'image_filters.dart';
import 'pdf_tools.dart';

// Top-level entry points for work done in a background isolate (see bg()).
// Each takes one record so it can be passed as a tear-off.

Uint8List processJob((Uint8List, PageFilter, int, int, int) a) =>
    processPage(a.$1, filter: a.$2, quarterTurns: a.$3, maxSide: a.$4, quality: a.$5);

Uint8List unlockJob((Uint8List, String) a) => PdfTools.unlock(a.$1, a.$2);

Uint8List mergeJob(List<Uint8List> files) => PdfTools.merge(files);

Uint8List organizeJob((Uint8List, List<PageRef>) a) => PdfTools.organize(a.$1, a.$2);

List<Uint8List> splitJob((Uint8List, List<List<int>>) a) => PdfTools.split(a.$1, a.$2);

Uint8List rotateJob((Uint8List, int) a) => PdfTools.rotate(a.$1, a.$2);

Uint8List cropJob((Uint8List, double, double, double, double) a) =>
    PdfTools.crop(a.$1, left: a.$2, top: a.$3, right: a.$4, bottom: a.$5);

Uint8List watermarkJob((Uint8List, String, double) a) =>
    PdfTools.watermark(a.$1, a.$2, opacity: a.$3);

Uint8List pageNumbersJob((Uint8List, PageNumberPosition, String) a) =>
    PdfTools.addPageNumbers(a.$1, position: a.$2, pattern: a.$3);

Uint8List protectJob((Uint8List, String) a) => PdfTools.protect(a.$1, a.$2);

Uint8List optimizeJob(Uint8List b) => PdfTools.optimize(b);

List<String> textJob(Uint8List b) => PdfTools.pageTexts(b);

int pageCountJob(Uint8List b) => PdfTools.pageCount(b);

Uint8List stampJob((Uint8List, Uint8List, int, Rect) a) =>
    PdfTools.stampImage(a.$1, a.$2, page: a.$3, box: a.$4);

Uint8List addTextJob((Uint8List, String, int, Offset, double, int) a) =>
    PdfTools.addText(a.$1, a.$2, page: a.$3, at: a.$4, fontSize: a.$5, color: a.$6);

Uint8List coverJob((Uint8List, Map<int, List<Rect>>) a) {
  var out = a.$1;
  for (final e in a.$2.entries) {
    out = PdfTools.coverBoxes(out, page: e.key, boxes: e.value);
  }
  return out;
}

Uint8List replaceJob((Uint8List, Map<int, Uint8List>) a) =>
    PdfTools.replaceWithImages(a.$1, a.$2);
