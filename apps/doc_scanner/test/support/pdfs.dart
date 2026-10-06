import 'dart:typed_data';
import 'dart:ui';

import 'package:doc_scanner/pdf_tools.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// A PDF whose page i says `prefix` followed by i+1 as real, extractable text.
Uint8List labelledPdf(int pages,
    {String prefix = 'Page ', Size size = const Size(595, 842)}) {
  final d = PdfDocument();
  d.pageSettings
    ..margins.all = 0
    ..orientation = size.width > size.height
        ? PdfPageOrientation.landscape
        : PdfPageOrientation.portrait
    ..size = size;
  for (var i = 0; i < pages; i++) {
    d.pages.add().graphics.drawString(
        '$prefix${i + 1}', PdfStandardFont(PdfFontFamily.helvetica, 24),
        bounds: const Rect.fromLTWH(40, 40, 300, 40));
  }
  final out = Uint8List.fromList(d.saveSync());
  d.dispose();
  return out;
}

/// Trimmed text of every page.
List<String> pageLabels(Uint8List pdf) =>
    PdfTools.pageTexts(pdf).map((t) => t.trim()).toList();

/// Expected labels for zero-based [indexes].
List<String> labelsFor(Iterable<int> indexes, {String prefix = 'Page '}) =>
    [for (final i in indexes) '$prefix${i + 1}'];
