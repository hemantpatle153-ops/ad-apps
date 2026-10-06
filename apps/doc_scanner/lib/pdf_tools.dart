import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// One page in an organized document: which source page, and how many
/// quarter turns to add on top of its own rotation.
class PageRef {
  const PageRef(this.index, [this.quarterTurns = 0]);
  final int index;
  final int quarterTurns;

  PageRef turned(int by) => PageRef(index, (quarterTurns + by) % 4);
}

enum PageNumberPosition { bottomCenter, bottomRight, topRight }

enum Corner { bottomRight, bottomLeft, bottomCenter, topRight }

/// Thrown when a PDF needs a password, or the one given is wrong.
class PasswordRequired implements Exception {
  const PasswordRequired();
  @override
  String toString() => 'This PDF is password protected.';
}

/// PDF tools that run fully on the phone (iLovePDF-style). Every function
/// takes and returns PDF bytes so they are easy to chain and test.
class PdfTools {
  PdfTools._();

  static PdfDocument open(Uint8List bytes, {String? password}) {
    try {
      return PdfDocument(inputBytes: bytes, password: password);
    } on ArgumentError catch (e) {
      if ('${e.message}'.toLowerCase().contains('password')) {
        throw const PasswordRequired();
      }
      rethrow;
    }
  }

  static Uint8List _save(PdfDocument doc) {
    final out = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    return out;
  }

  static int pageCount(Uint8List bytes, {String? password}) {
    final doc = open(bytes, password: password);
    final n = doc.pages.count;
    doc.dispose();
    return n;
  }

  static bool isEncrypted(Uint8List bytes) {
    try {
      open(bytes).dispose();
      return false;
    } on PasswordRequired {
      return true;
    }
  }

  /// Copies [src] onto a new page of [dst], optionally cropped by [crop]
  /// (points from each edge). The page's rotation plus [extraTurns] is
  /// baked into the content, so output pages are never "rotated" pages and
  /// later stamps land where the user saw them.
  static void _copyPage(PdfDocument dst, PdfPage src,
      {int extraTurns = 0, Rect? crop}) {
    final full = src.size;
    final c = crop ?? Rect.zero;
    final w = full.width - c.left - c.right;
    final h = full.height - c.top - c.bottom;
    final turns = (src.rotation.index + extraTurns) % 4;
    final size = turns.isOdd ? Size(h, w) : Size(w, h);
    final section = dst.sections!.add();
    section.pageSettings
      ..margins.all = 0
      ..orientation = size.width > size.height
          ? PdfPageOrientation.landscape
          : PdfPageOrientation.portrait
      ..size = size;
    final g = section.pages.add().graphics;
    switch (turns) {
      case 1:
        g.translateTransform(h, 0);
        g.rotateTransform(90);
      case 2:
        g.translateTransform(w, h);
        g.rotateTransform(180);
      case 3:
        g.translateTransform(0, w);
        g.rotateTransform(270);
    }
    g.drawPdfTemplate(src.createTemplate(), Offset(-c.left, -c.top), full);
  }

  /// Opens [bytes] for drawing on; rotated pages are baked first so
  /// fractional positions match what the user saw on screen.
  static PdfDocument _openFlat(Uint8List bytes) {
    final doc = open(bytes);
    var rotated = false;
    for (var i = 0; i < doc.pages.count && !rotated; i++) {
      rotated = doc.pages[i].rotation != PdfPageRotateAngle.rotateAngle0;
    }
    if (!rotated) return doc;
    final out = _newDoc();
    for (var i = 0; i < doc.pages.count; i++) {
      _copyPage(out, doc.pages[i]);
    }
    doc.dispose();
    final flat = _save(out);
    return open(flat);
  }

  static PdfDocument _newDoc() {
    final d = PdfDocument();
    d.pageSettings.margins.all = 0;
    d.compressionLevel = PdfCompressionLevel.best;
    return d;
  }

  /// Joins several PDFs into one, in order.
  static Uint8List merge(List<Uint8List> files) {
    final out = _newDoc();
    for (final bytes in files) {
      final src = open(bytes);
      for (var i = 0; i < src.pages.count; i++) {
        _copyPage(out, src.pages[i]);
      }
      src.dispose();
    }
    return _save(out);
  }

  /// Builds a new PDF from [pages] of [bytes]: reorder, drop, duplicate
  /// and rotate pages in one pass.
  static Uint8List organize(Uint8List bytes, List<PageRef> pages) {
    if (pages.isEmpty) throw ArgumentError('Keep at least one page.');
    final src = open(bytes);
    final out = _newDoc();
    for (final p in pages) {
      _copyPage(out, src.pages[p.index], extraTurns: p.quarterTurns);
    }
    src.dispose();
    return _save(out);
  }

  /// Keeps only the given zero-based pages.
  static Uint8List extract(Uint8List bytes, List<int> pages) =>
      organize(bytes, [for (final p in pages) PageRef(p)]);

  /// One output PDF per group of zero-based page indexes.
  static List<Uint8List> split(Uint8List bytes, List<List<int>> groups) =>
      [for (final g in groups) extract(bytes, g)];

  static Uint8List removePages(Uint8List bytes, Set<int> remove) {
    final n = pageCount(bytes);
    final keep = [for (var i = 0; i < n; i++) if (!remove.contains(i)) i];
    return extract(bytes, keep);
  }

  /// Rotates the chosen pages (all when [pages] is null) clockwise.
  static Uint8List rotate(Uint8List bytes, int quarterTurns,
      {Set<int>? pages}) {
    final n = pageCount(bytes);
    return organize(bytes, [
      for (var i = 0; i < n; i++)
        PageRef(i, pages == null || pages.contains(i) ? quarterTurns % 4 : 0),
    ]);
  }

  /// Trims every page by a fraction of its width/height on each edge.
  static Uint8List crop(Uint8List bytes,
      {double left = 0, double top = 0, double right = 0, double bottom = 0}) {
    final src = open(bytes);
    final out = _newDoc();
    for (var i = 0; i < src.pages.count; i++) {
      final page = src.pages[i];
      final s = page.size;
      _copyPage(out, page,
          crop: Rect.fromLTRB(s.width * left, s.height * top,
              s.width * right, s.height * bottom));
    }
    src.dispose();
    return _save(out);
  }

  static Uint8List watermark(Uint8List bytes, String text,
      {double opacity = 0.25, double fontSize = 56}) {
    final doc = _openFlat(bytes);
    final font = PdfStandardFont(PdfFontFamily.helvetica, fontSize,
        style: PdfFontStyle.bold);
    final w = font.measureString(text);
    for (var i = 0; i < doc.pages.count; i++) {
      final page = doc.pages[i];
      final s = page.getClientSize();
      final g = page.graphics;
      final state = g.save();
      g.setTransparency(opacity);
      g.translateTransform(s.width / 2, s.height / 2);
      g.rotateTransform(-45);
      g.drawString(text, font,
          brush: PdfSolidBrush(PdfColor(200, 30, 30)),
          bounds: Rect.fromLTWH(-w.width / 2, -w.height / 2, w.width, w.height));
      g.restore(state);
    }
    return _save(doc);
  }

  static String pageLabel(int page, int total, String pattern) => pattern
      .replaceAll('{n}', '$page')
      .replaceAll('{total}', '$total');

  static Uint8List addPageNumbers(Uint8List bytes,
      {PageNumberPosition position = PageNumberPosition.bottomCenter,
      String pattern = '{n} / {total}',
      int startAt = 1}) {
    final doc = _openFlat(bytes);
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final total = doc.pages.count;
    for (var i = 0; i < total; i++) {
      final page = doc.pages[i];
      final s = page.getClientSize();
      final label = pageLabel(i + startAt, total + startAt - 1, pattern);
      final w = font.measureString(label).width;
      final x = switch (position) {
        PageNumberPosition.bottomCenter => (s.width - w) / 2,
        _ => s.width - w - 28,
      };
      final y = position == PageNumberPosition.topRight ? 18.0 : s.height - 30;
      page.graphics.drawString(label, font,
          brush: PdfSolidBrush(PdfColor(60, 60, 60)),
          bounds: Rect.fromLTWH(x, y, w + 2, 16));
    }
    return _save(doc);
  }

  /// Encrypts with AES-256. Without a password the file won't open.
  static Uint8List protect(Uint8List bytes, String password) {
    if (password.isEmpty) throw ArgumentError('Enter a password.');
    final doc = open(bytes);
    doc.security
      ..algorithm = PdfEncryptionAlgorithm.aesx256Bit
      ..userPassword = password
      ..ownerPassword = password;
    return _save(doc);
  }

  /// Removes the password (the right one must be given).
  static Uint8List unlock(Uint8List bytes, String password) {
    final PdfDocument doc;
    try {
      doc = open(bytes, password: password);
    } on PasswordRequired {
      throw const PasswordRequired();
    } catch (_) {
      throw const PasswordRequired();
    }
    doc.security
      ..userPassword = ''
      ..ownerPassword = '';
    // Re-saving into a fresh document drops the encryption dictionary.
    final out = _newDoc();
    for (var i = 0; i < doc.pages.count; i++) {
      _copyPage(out, doc.pages[i]);
    }
    doc.dispose();
    return _save(out);
  }

  /// Places an image (signature, stamp) on one page. [box] is in
  /// fractions of the page (0..1) so it doesn't depend on screen size.
  static Uint8List stampImage(Uint8List bytes, Uint8List png,
      {required int page, required Rect box}) {
    final doc = _openFlat(bytes);
    final p = doc.pages[page];
    final s = p.getClientSize();
    p.graphics.drawImage(
        PdfBitmap(png),
        Rect.fromLTWH(box.left * s.width, box.top * s.height,
            box.width * s.width, box.height * s.height));
    return _save(doc);
  }

  /// Writes text on a page at a fractional position.
  static Uint8List addText(Uint8List bytes, String text,
      {required int page,
      required Offset at,
      double fontSize = 14,
      int color = 0xFF000000}) {
    final doc = _openFlat(bytes);
    final p = doc.pages[page];
    final s = p.getClientSize();
    final font = PdfStandardFont(PdfFontFamily.helvetica, fontSize);
    final m = font.measureString(text);
    p.graphics.drawString(text, font,
        brush: PdfSolidBrush(PdfColor(
            (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF)),
        bounds: Rect.fromLTWH(
            at.dx * s.width, at.dy * s.height, m.width + 4, m.height + 4));
    return _save(doc);
  }

  /// Draws filled boxes over parts of a page. On its own this only hides
  /// content visually; the redact tool also flattens the page to an image
  /// so the text underneath is gone for real.
  static Uint8List coverBoxes(Uint8List bytes,
      {required int page, required List<Rect> boxes}) {
    final doc = _openFlat(bytes);
    final p = doc.pages[page];
    final s = p.getClientSize();
    for (final b in boxes) {
      p.graphics.drawRectangle(
          brush: PdfSolidBrush(PdfColor(0, 0, 0)),
          bounds: Rect.fromLTWH(b.left * s.width, b.top * s.height,
              b.width * s.width, b.height * s.height));
    }
    return _save(doc);
  }

  /// Re-saves with maximum stream compression and drops unused objects.
  /// Lossless; also fixes many slightly damaged files ("repair").
  static Uint8List optimize(Uint8List bytes) {
    final doc = open(bytes);
    doc.compressionLevel = PdfCompressionLevel.best;
    doc.fileStructure.incrementalUpdate = false;
    return _save(doc);
  }

  /// Text of each page (empty for scanned pages without a text layer).
  static List<String> pageTexts(Uint8List bytes, {String? password}) {
    final doc = open(bytes, password: password);
    final ex = PdfTextExtractor(doc);
    final out = [
      for (var i = 0; i < doc.pages.count; i++)
        ex.extractText(startPageIndex: i, endPageIndex: i),
    ];
    doc.dispose();
    return out;
  }

  static Size pageSize(Uint8List bytes, int page) {
    final doc = open(bytes);
    final s = doc.pages[page].size;
    doc.dispose();
    return s;
  }

  /// Replaces pages with full-page images (used after rasterizing for
  /// strong compression or real redaction). [images] maps page index to
  /// JPEG/PNG bytes; other pages are copied as they are.
  static Uint8List replaceWithImages(
      Uint8List bytes, Map<int, Uint8List> images) {
    final src = open(bytes);
    final out = _newDoc();
    for (var i = 0; i < src.pages.count; i++) {
      final page = src.pages[i];
      final img = images[i];
      if (img == null) {
        _copyPage(out, page);
        continue;
      }
      // The rendered image already shows the page's rotation.
      var size = page.size;
      if (page.rotation.index.isOdd) size = Size(size.height, size.width);
      final section = out.sections!.add();
      section.pageSettings
        ..margins.all = 0
        ..orientation = size.width > size.height
            ? PdfPageOrientation.landscape
            : PdfPageOrientation.portrait
        ..size = size;
      section.pages.add().graphics.drawImage(
          PdfBitmap(img), Rect.fromLTWH(0, 0, size.width, size.height));
    }
    src.dispose();
    return _save(out);
  }
}
