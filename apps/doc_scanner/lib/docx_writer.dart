import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// A minimal Word (.docx) file: one paragraph per line, a page break
/// between [pages]. Opens in Word, Google Docs and WPS.
Uint8List buildDocx(List<String> pages) {
  final body = StringBuffer();
  for (var p = 0; p < pages.length; p++) {
    if (p > 0) body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    for (final line in pages[p].split('\n')) {
      body.write('<w:p><w:r><w:t xml:space="preserve">${_x(line.trimRight())}</w:t></w:r></w:p>');
    }
  }
  const ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';
  const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';
  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body<w:sectPr/></w:body></w:document>';
  final a = Archive();
  void add(String name, String text) {
    final data = utf8.encode(text);
    a.addFile(ArchiveFile(name, data.length, data));
  }

  add('[Content_Types].xml', ct);
  add('_rels/.rels', rels);
  add('word/document.xml', doc);
  return Uint8List.fromList(ZipEncoder().encode(a));
}

/// Reads the plain text back out of a .docx (one line per paragraph).
String readDocxText(Uint8List bytes) {
  final a = ZipDecoder().decodeBytes(bytes);
  final f = a.findFile('word/document.xml');
  if (f == null) throw const FormatException('Not a Word document.');
  final xml = utf8.decode(f.content as List<int>);
  final paras = RegExp(r'<w:p[ >].*?</w:p>|<w:p/>', dotAll: true)
      .allMatches(xml)
      .map((m) => RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true)
          .allMatches(m.group(0)!)
          .map((t) => t.group(1)!)
          .join())
      .map((s) => s
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&'));
  return paras.join('\n');
}
