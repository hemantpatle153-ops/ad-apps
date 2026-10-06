import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:doc_scanner/docx_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('docx has the required parts', () {
    final a = ZipDecoder().decodeBytes(buildDocx(['Hello']));
    expect(a.findFile('[Content_Types].xml'), isNotNull);
    expect(a.findFile('_rels/.rels'), isNotNull);
    expect(a.findFile('word/document.xml'), isNotNull);
  });

  test('text round-trips, including special characters', () {
    final docx = buildDocx(['Line 1\nTom & Jerry <3', 'Second page']);
    expect(readDocxText(docx),
        'Line 1\nTom & Jerry <3\n\nSecond page');
  });

  test('control characters are dropped', () {
    expect(readDocxText(buildDocx(['a\u0001b'])), 'ab');
  });

  test('a non-Word zip is rejected', () {
    final zip = ZipEncoder().encode(Archive()..addFile(ArchiveFile('x.txt', 1, [65])));
    expect(() => readDocxText(Uint8List.fromList(zip)), throwsFormatException);
  });
}
