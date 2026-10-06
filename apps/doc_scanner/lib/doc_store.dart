import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A saved PDF in the app's private documents folder.
class SavedDoc {
  SavedDoc(this.file, this.modified, this.bytes);
  final File file;
  final DateTime modified;
  final int bytes;

  String get name {
    final base = file.uri.pathSegments.last;
    return base.endsWith('.pdf') ? base.substring(0, base.length - 4) : base;
  }
}

/// A line of recognized text on a page image, in image pixels.
class OcrLine {
  const OcrLine(this.text, this.box);
  final String text;
  final Rect box;
}

/// Recognized text of one page image.
class PageText {
  const PageText(this.width, this.height, this.lines);
  final int width;
  final int height;
  final List<OcrLine> lines;

  String get plain => lines.map((l) => l.text).join('\n');
}

/// The built-in PDF font only covers Latin-1; other characters become '?'
/// in the hidden text layer (the page image itself is unchanged).
String latin1Safe(String s) =>
    String.fromCharCodes(s.runes.map((r) => r < 256 ? r : 0x3F));

enum PageSize {
  a4('A4', PdfPageFormat.a4),
  letter('Letter', PdfPageFormat.letter),
  fit('Fit to image', null);

  const PageSize(this.label, this.format);
  final String label;
  final PdfPageFormat? format;
}

/// Lists, writes, renames and deletes the PDFs. Everything stays on the phone.
class DocStore {
  DocStore._();
  static final DocStore instance = DocStore._();

  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final d = Directory('${root.path}/pdfs');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<SavedDoc>> list() async {
    final d = await _dir();
    final docs = <SavedDoc>[];
    await for (final e in d.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.pdf')) {
        final st = await e.stat();
        docs.add(SavedDoc(e, st.modified, st.size));
      }
    }
    docs.sort((a, b) => b.modified.compareTo(a.modified));
    return docs;
  }

  static String sanitize(String name) {
    final s = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_');
    return s.isEmpty ? 'Scan' : s;
  }

  Future<File> _uniqueFile(String name) async {
    final d = await _dir();
    final base = sanitize(name);
    var f = File('${d.path}/$base.pdf');
    var n = 2;
    while (await f.exists()) {
      f = File('${d.path}/$base ($n).pdf');
      n++;
    }
    return f;
  }

  /// Builds one PDF page per image, scaled to fit with a small margin.
  /// When [text] is given (one entry per image, from OCR), an invisible
  /// text layer is placed over each page so the PDF is searchable and its
  /// text can be selected and copied, like Adobe Scan.
  static Future<Uint8List> buildPdf(List<Uint8List> images, PageSize size,
      {List<PageText?>? text}) async {
    final doc = pw.Document(title: 'Scan', creator: 'Document Scanner');
    for (var i = 0; i < images.length; i++) {
      final img = pw.MemoryImage(images[i]);
      final iw = (img.width ?? 595).toDouble();
      final ih = (img.height ?? 842).toDouble();
      final format = size.format ?? PdfPageFormat(iw, ih);
      final margin = size.format == null ? 0.0 : 18.0;
      final cw = format.width - 2 * margin;
      final ch = format.height - 2 * margin;
      final scale = (cw / iw) < (ch / ih) ? cw / iw : ch / ih;
      final dw = iw * scale, dh = ih * scale;
      final ox = (cw - dw) / 2, oy = (ch - dh) / 2;
      final pageText = text != null && i < text.length ? text[i] : null;
      // OCR boxes are in the recognizer's pixels; map them to this image.
      final tScale = pageText == null || pageText.width == 0
          ? scale
          : scale * iw / pageText.width;
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin),
        build: (_) => pw.SizedBox(
          width: cw,
          height: ch,
          child: pw.Stack(children: [
            pw.Positioned(
              left: ox,
              top: oy,
              child: pw.Image(img, width: dw, height: dh),
            ),
            if (pageText != null)
              for (final l in pageText.lines)
                if (l.text.trim().isNotEmpty)
                  pw.Positioned(
                    left: ox + l.box.left * tScale,
                    top: oy + l.box.top * tScale,
                    child: pw.Text(
                      latin1Safe(l.text),
                      softWrap: false,
                      style: pw.TextStyle(
                        fontSize: (l.box.height * tScale * 0.75)
                            .clamp(2.0, 72.0),
                        renderingMode: PdfTextRenderingMode.invisible,
                      ),
                    ),
                  ),
          ]),
        ),
      ));
    }
    return doc.save();
  }

  /// Both sides of an ID card at real size on one A4 page, for photocopies.
  static Future<Uint8List> buildIdCardPdf(Uint8List front, Uint8List? back) {
    final doc = pw.Document(title: 'ID card', creator: 'Document Scanner');
    const cardWidth = 85.6 * PdfPageFormat.mm;
    pw.Widget side(Uint8List b) => pw.Container(
          width: cardWidth,
          margin: const pw.EdgeInsets.all(24),
          child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.contain),
        );
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [side(front), if (back != null) side(back)],
      ),
    ));
    return doc.save();
  }

  /// A plain text PDF (used for Word to PDF), one paragraph per line.
  static Future<Uint8List> buildTextPdf(String title, String text) {
    final doc = pw.Document(title: title, creator: 'Document Scanner');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(56),
      build: (_) => [
        for (final para in text.split('\n'))
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(latin1Safe(para),
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
          ),
      ],
    ));
    return doc.save();
  }

  Future<File> savePdf(String name, Uint8List pdf) async {
    final f = await _uniqueFile(name);
    return f.writeAsBytes(pdf, flush: true);
  }

  Future<File> rename(SavedDoc doc, String newName) async {
    final f = await _uniqueFile(newName);
    final text = await _textFile(doc.file);
    final renamed = await doc.file.rename(f.path);
    if (await text.exists()) await text.rename((await _textFile(renamed)).path);
    return renamed;
  }

  Future<void> delete(SavedDoc doc) async {
    final text = await _textFile(doc.file);
    if (await text.exists()) await text.delete();
    await doc.file.delete();
  }

  // Recognized text lives next to each PDF so documents can be searched
  // by their content.
  Future<File> _textFile(File pdf) async {
    final d = Directory('${(await _dir()).path}/.text');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/${pdf.uri.pathSegments.last}.txt');
  }

  Future<void> saveText(File pdf, String text) async {
    if (text.trim().isEmpty) return;
    await (await _textFile(pdf)).writeAsString(text, flush: true);
  }

  Future<String> readText(File pdf) async {
    final f = await _textFile(pdf);
    return await f.exists() ? f.readAsString() : '';
  }

  /// Writes a non-PDF output (images, Word, text, contacts) to a cache
  /// folder so it can be shared.
  Future<File> saveExport(String fileName, List<int> bytes) async {
    final root = await getTemporaryDirectory();
    final d = Directory('${root.path}/exports');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/${sanitize(fileName)}').writeAsBytes(bytes, flush: true);
  }
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
