import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:doc_scanner/docx_writer.dart';
import 'package:flutter_test/flutter_test.dart';

String part(Uint8List docx, String name) =>
    utf8.decode(ZipDecoder().decodeBytes(docx).findFile(name)!.content as List<int>);

/// What readDocxText should return for [pages].
String expected(List<String> pages) => [
      for (var p = 0; p < pages.length; p++) ...[
        if (p > 0) '',
        for (final l in pages[p].split('\n'))
          l.trimRight().replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''),
      ]
    ].join('\n');

final runes = 'abcXYZ 019 &<>"\'.,;:-_!?\u20B9\u00E9\u0939\u{1F600}\t\u0001'.runes.toList();

void main() {
  group('package parts', () {
    final docx = buildDocx(['Hello', 'World']);
    final a = ZipDecoder().decodeBytes(docx);
    test('exactly three parts', () {
      expect(a.files.map((f) => f.name).toSet(),
          {'[Content_Types].xml', '_rels/.rels', 'word/document.xml'});
    });
    test('content types declare the main document', () {
      final ct = part(docx, '[Content_Types].xml');
      expect(ct, contains('PartName="/word/document.xml"'));
      expect(ct, contains('wordprocessingml.document.main+xml'));
      expect(ct, contains('Extension="rels"'));
    });
    test('package relationship points to word/document.xml', () {
      final rels = part(docx, '_rels/.rels');
      expect(rels, contains('Target="word/document.xml"'));
      expect(rels, contains('relationships/officeDocument'));
    });
    test('document has body and section properties', () {
      final d = part(docx, 'word/document.xml');
      expect(d, startsWith('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'));
      expect(d, contains('<w:body>'));
      expect(d, endsWith('<w:sectPr/></w:body></w:document>'));
    });
    test('zip starts with the PK signature', () {
      expect(docx.sublist(0, 2), [0x50, 0x4B]);
    });
  });

  group('paragraph and page break counts', () {
    for (final pages in [1, 2, 3, 5, 8]) {
      for (final lines in [1, 2, 4, 7]) {
        test('$pages pages of $lines lines', () {
          final input = [
            for (var p = 0; p < pages; p++)
              [for (var l = 0; l < lines; l++) 'p$p l$l'].join('\n')
          ];
          final d = part(buildDocx(input), 'word/document.xml');
          expect('<w:br w:type="page"/>'.allMatches(d).length, pages - 1);
          expect('<w:p>'.allMatches(d).length, pages * lines + pages - 1);
          expect(readDocxText(buildDocx(input)), expected(input));
        });
      }
    }
    test('no pages gives an empty body', () {
      final d = buildDocx(const []);
      expect(part(d, 'word/document.xml'), contains('<w:body><w:sectPr/></w:body>'));
      expect(readDocxText(d), '');
    });
  });

  group('escaping', () {
    const cases = {
      'a & b': 'a &amp; b',
      '<tag>': '&lt;tag&gt;',
      '1 < 2 > 0': '1 &lt; 2 &gt; 0',
      '&amp;': '&amp;amp;',
      '&lt;': '&amp;lt;',
      'x\u0000y': 'xy',
      'x\u000By': 'xy',
      'x\u001Fy': 'xy',
      'x\ty': 'x\ty',
      'trailing   ': 'trailing',
      '  leading': '  leading',
    };
    cases.forEach((raw, xml) {
      test('${jsonEncode(raw)} is written as ${jsonEncode(xml)}', () {
        final d = part(buildDocx([raw]), 'word/document.xml');
        expect(d, contains('<w:t xml:space="preserve">$xml</w:t>'));
      });
    });
  });

  group('special text round-trips', () {
    const samples = [
      'Tom & Jerry',
      '<script>alert(1)</script>',
      'Price: ₹ 950',
      'café',
      'नमस्ते',
      'emoji \u{1F600}',
      '"quoted" \'single\'',
      '&amp; already escaped',
      '',
      '   ',
      'a\r\nb',
    ];
    for (final s in samples) {
      test(jsonEncode(s), () {
        expect(readDocxText(buildDocx([s])), expected([s]));
      });
    }
  });

  group('seeded random documents round-trip', () {
    for (var seed = 0; seed < 50; seed++) {
      test('seed $seed', () {
        final r = Random(seed);
        final pages = [
          for (var p = 0; p < 1 + r.nextInt(4); p++)
            [
              for (var l = 0; l < 1 + r.nextInt(6); l++)
                String.fromCharCodes([
                  for (var c = 0; c < r.nextInt(30); c++) runes[r.nextInt(runes.length)]
                ])
            ].join('\n')
        ];
        expect(readDocxText(buildDocx(pages)), expected(pages));
      });
    }
  });

  group('readDocxText rejects', () {
    test('a zip without word/document.xml', () {
      final a = Archive()..addFile(ArchiveFile('word/other.xml', 1, [65]));
      expect(() => readDocxText(Uint8List.fromList(ZipEncoder().encode(a))),
          throwsFormatException);
    });
    test('an empty zip', () {
      expect(() => readDocxText(Uint8List.fromList(ZipEncoder().encode(Archive()))),
          throwsFormatException);
    });
  });

  group('readDocxText on hand-made documents', () {
    Uint8List docWith(String body) {
      final xml = utf8.encode('<w:document><w:body>$body</w:body></w:document>');
      final a = Archive()..addFile(ArchiveFile('word/document.xml', xml.length, xml));
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    const cases = {
      '<w:p><w:r><w:t>Hi</w:t></w:r></w:p>': 'Hi',
      '<w:p><w:r><w:t>a</w:t></w:r><w:r><w:t xml:space="preserve"> b</w:t></w:r></w:p>': 'a b',
      '<w:p/><w:p><w:r><w:t>x</w:t></w:r></w:p>': '\nx',
      '<w:p w:rsidR="1"><w:r><w:t>attr</w:t></w:r></w:p>': 'attr',
      '<w:p><w:r><w:t>&lt;&amp;&gt;</w:t></w:r></w:p>': '<&>',
      '<w:p><w:r><w:t>1</w:t></w:r></w:p><w:p><w:r><w:t>2</w:t></w:r></w:p>': '1\n2',
      '<w:tbl></w:tbl>': '',
    };
    cases.forEach((body, want) {
      test(body, () => expect(readDocxText(docWith(body)), want));
    });
  });
}
