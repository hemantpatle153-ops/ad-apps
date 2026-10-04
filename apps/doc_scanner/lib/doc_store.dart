import 'dart:io';
import 'dart:typed_data';

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
  static Future<Uint8List> buildPdf(
      List<Uint8List> images, PageSize size) async {
    final doc = pw.Document(title: 'Scan', creator: 'Document Scanner');
    for (final bytes in images) {
      final img = pw.MemoryImage(bytes);
      final format = size.format ??
          PdfPageFormat(
            (img.width ?? 595).toDouble(),
            (img.height ?? 842).toDouble(),
          );
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: size.format == null ? pw.EdgeInsets.zero : const pw.EdgeInsets.all(18),
        build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
      ));
    }
    return doc.save();
  }

  Future<File> savePdf(String name, Uint8List pdf) async {
    final f = await _uniqueFile(name);
    return f.writeAsBytes(pdf, flush: true);
  }

  Future<File> rename(SavedDoc doc, String newName) async {
    final f = await _uniqueFile(newName);
    return doc.file.rename(f.path);
  }

  Future<void> delete(SavedDoc doc) => doc.file.delete();
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
