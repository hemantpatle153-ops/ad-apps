import 'dart:io';

import 'package:doc_scanner/doc_store.dart';
import 'package:doc_scanner/pdf_tools.dart';
import 'package:doc_scanner/ui_helpers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';

import 'support/pdfs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sanitize', () {
    const cases = {
      'Scan': 'Scan',
      '  Bill  ': 'Bill',
      'a/b': 'a_b',
      r'a\b': 'a_b',
      'a:b': 'a_b',
      'a*b?': 'a_b_',
      '"quote"': '_quote_',
      '<x>': '_x_',
      'a|b': 'a_b',
      'line\nbreak': 'line_break',
      'tab\tbed': 'tab_bed',
      '': 'Scan',
      '\n': 'Scan',
      'Résumé 2024': 'Résumé 2024',
      'हिन्दी': 'हिन्दी',
      'Bill (2).pdf': 'Bill (2).pdf',
      '///': '___',
    };
    cases.forEach((raw, want) {
      test(raw.replaceAll('\n', r'\n').replaceAll('\t', r'\t'), () {
        final s = DocStore.sanitize(raw);
        expect(s, want);
        expect(s, isNot(matches(RegExp(r'[\\/:*?"<>|\n\r\t]'))));
      });
    });
  });

  group('formatBytes', () {
    const cases = {
      0: '0 B',
      1: '1 B',
      1023: '1023 B',
      1024: '1 KB',
      1536: '2 KB',
      10 * 1024: '10 KB',
      1024 * 1024 - 1: '1024 KB',
      1024 * 1024: '1.0 MB',
      1572864: '1.5 MB',
      25 * 1024 * 1024: '25.0 MB',
      1024 * 1024 * 1024: '1024.0 MB',
    };
    cases.forEach((b, want) => test('$b', () => expect(formatBytes(b), want)));
  });

  group('latin1Safe', () {
    const cases = {
      'plain ASCII': 'plain ASCII',
      'café üñ': 'café üñ',
      '₹ 950': '? 950',
      'नम': '??',
      'a\u{1F600}b': 'a?b',
      '': '',
      'ÿĀ': 'ÿ?',
    };
    cases.forEach((raw, want) {
      test(raw, () => expect(latin1Safe(raw), want));
    });
  });

  group('PageText.plain', () {
    for (final n in [0, 1, 2, 5]) {
      test('$n lines', () {
        final t = PageText(100, 100, [
          for (var i = 0; i < n; i++) OcrLine('line $i', Rect.fromLTWH(0, i * 10, 50, 8))
        ]);
        expect(t.plain, [for (var i = 0; i < n; i++) 'line $i'].join('\n'));
      });
    }
  });

  group('SavedDoc.name', () {
    const cases = {
      '/x/pdfs/Bill.pdf': 'Bill',
      '/x/pdfs/Scan 2024-01-02 10.30.pdf': 'Scan 2024-01-02 10.30',
      '/x/pdfs/Bill (2).pdf': 'Bill (2)',
      '/x/pdfs/notes.PDF': 'notes.PDF',
      '/x/pdfs/a.pdf.pdf': 'a.pdf',
    };
    cases.forEach((path, want) {
      test(path, () => expect(SavedDoc(File(path), DateTime(2024), 0).name, want));
    });
  });

  group('PageSize', () {
    test('A4 format', () => expect(PageSize.a4.format, PdfPageFormat.a4));
    test('Letter format', () => expect(PageSize.letter.format, PdfPageFormat.letter));
    test('fit has no fixed format', () => expect(PageSize.fit.format, isNull));
    test('labels are unique', () {
      expect(PageSize.values.map((s) => s.label).toSet().length, PageSize.values.length);
    });
  });

  group('buildPdf', () {
    Uint8List jpg(int w, int h) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));
    for (final size in PageSize.values) {
      for (final n in [1, 3]) {
        test('$n images on ${size.label}', () async {
          final out = await DocStore.buildPdf([for (var i = 0; i < n; i++) jpg(300, 200)], size);
          expect(PdfTools.pageCount(out), n);
          final s = PdfTools.pageSize(out, 0);
          if (size == PageSize.fit) {
            expect(s.width, closeTo(300, 1));
            expect(s.height, closeTo(200, 1));
          } else {
            expect(s.width, closeTo(size.format!.width, 1));
            expect(s.height, closeTo(size.format!.height, 1));
          }
        });
      }
    }
    test('text for some pages only', () async {
      final out = await DocStore.buildPdf([jpg(200, 200), jpg(200, 200)], PageSize.a4, text: [
        const PageText(200, 200, [OcrLine('Hello', Rect.fromLTWH(10, 10, 80, 20))]),
      ]);
      final t = PdfTools.pageTexts(out);
      expect(t[0], contains('Hello'));
      expect(t[1].trim(), isEmpty);
    });
  });

  group('buildTextPdf', () {
    for (final lines in [1, 10, 200]) {
      test('$lines lines', () async {
        final text = [for (var i = 0; i < lines; i++) 'Paragraph $i'].join('\n');
        final out = await DocStore.buildTextPdf('T', text);
        final count = PdfTools.pageCount(out);
        expect(count, lines > 60 ? greaterThan(1) : 1);
        // The extractor may break lines between words; compare word by word.
        final all = PdfTools.pageTexts(out).join(' ').split(RegExp(r'\s+')).join(' ');
        expect(all, contains('Paragraph 0'));
        expect(all, contains('Paragraph ${lines - 1}'));
      });
    }
  });

  group('ID card', () {
    test('front only', () async {
      final f = Uint8List.fromList(img.encodeJpg(img.Image(width: 86, height: 54)));
      final out = await DocStore.buildIdCardPdf(f, null);
      expect(PdfTools.pageCount(out), 1);
      expect(PdfTools.pageSize(out, 0).width, closeTo(PdfPageFormat.a4.width, 1));
    });
  });

  group('friendlyError', () {
    test('password', () {
      expect(friendlyError(const PasswordRequired()), 'Wrong password, or the PDF is locked.');
    });
    test('format', () => expect(friendlyError(const FormatException('Bad pages')), 'Bad pages'));
    test('argument', () => expect(friendlyError(ArgumentError('Keep one')), 'Keep one'));
    test('other', () => expect(friendlyError(StateError('x')), 'Something went wrong: Bad state: x'));
  });

  group('store on disk', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('doc_store_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => root.path);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      root.deleteSync(recursive: true);
    });
    final store = DocStore.instance;
    final pdf = labelledPdf(2);

    test('saved PDFs are listed with their bytes', () async {
      final f = await store.savePdf('Bill', pdf);
      expect(f.path, '${root.path}/pdfs/Bill.pdf');
      final docs = await store.list();
      expect(docs.map((d) => d.name), ['Bill']);
      expect(docs.single.bytes, pdf.length);
      expect(pageLabels(await docs.single.file.readAsBytes()), labelsFor([0, 1]));
    });

    test('same name gets a number', () async {
      final names = [
        for (var i = 0; i < 4; i++) (await store.savePdf('Bill', pdf)).uri.pathSegments.last
      ];
      expect(names, ['Bill.pdf', 'Bill (2).pdf', 'Bill (3).pdf', 'Bill (4).pdf']);
    });

    test('names are sanitized', () async {
      final f = await store.savePdf('a/b:c', pdf);
      expect(f.uri.pathSegments.last, 'a_b_c.pdf');
    });

    test('list skips non-PDF files and sorts newest first', () async {
      final a = await store.savePdf('Old', pdf);
      final b = await store.savePdf('New', pdf);
      a.setLastModifiedSync(DateTime(2020));
      b.setLastModifiedSync(DateTime(2024));
      File('${root.path}/pdfs/notes.txt').writeAsStringSync('x');
      expect((await store.list()).map((d) => d.name), ['New', 'Old']);
    });

    test('text round-trips and follows rename', () async {
      final f = await store.savePdf('Doc', pdf);
      await store.saveText(f, 'Invoice 42');
      expect(await store.readText(f), 'Invoice 42');
      final doc = (await store.list()).single;
      final renamed = await store.rename(doc, 'Renamed');
      expect(renamed.uri.pathSegments.last, 'Renamed.pdf');
      expect(await store.readText(renamed), 'Invoice 42');
      expect(await store.readText(f), '');
    });

    test('blank text is not saved', () async {
      final f = await store.savePdf('Doc', pdf);
      await store.saveText(f, '  \n ');
      expect(await store.readText(f), '');
    });

    test('rename to a taken name gets a number', () async {
      await store.savePdf('A', pdf);
      await store.savePdf('B', pdf);
      final b = (await store.list()).firstWhere((d) => d.name == 'B');
      final r = await store.rename(b, 'A');
      expect(r.uri.pathSegments.last, 'A (2).pdf');
    });

    test('delete removes the PDF and its text', () async {
      final f = await store.savePdf('Gone', pdf);
      await store.saveText(f, 'words');
      await store.delete((await store.list()).single);
      expect(await store.list(), isEmpty);
      expect(await store.readText(f), '');
    });

    test('exports go to the cache folder', () async {
      final f = await store.saveExport('card?.vcf', [65, 66]);
      expect(f.path, '${root.path}/exports/card_.vcf');
      expect(f.readAsBytesSync(), [65, 66]);
    });
  });
}
