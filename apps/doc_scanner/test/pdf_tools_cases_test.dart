import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:doc_scanner/jobs.dart';
import 'package:doc_scanner/page_ranges.dart';
import 'package:doc_scanner/pdf_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/pdfs.dart';

void main() {
  // Generated once and reused; every tool returns new bytes.
  final pdfs = {for (final n in [1, 2, 3, 5, 8]) n: labelledPdf(n)};

  group('pageCount', () {
    for (final n in [1, 2, 3, 5, 8, 13]) {
      test('$n pages', () {
        expect(PdfTools.pageCount(labelledPdf(n)), n);
        expect(pageCountJob(labelledPdf(n)), n);
      });
    }
  });

  group('merge', () {
    final combos = <List<int>>[
      [1],
      [1, 1],
      [2, 3],
      [3, 2],
      [1, 2, 3],
      [5, 1],
      [8, 8],
      [1, 1, 1, 1],
    ];
    for (final c in combos) {
      test('files of ${c.join('+')} pages', () {
        final files = [
          for (var k = 0; k < c.length; k++) labelledPdf(c[k], prefix: 'F$k-')
        ];
        final out = mergeJob(files);
        expect(PdfTools.pageCount(out), c.fold<int>(0, (s, n) => s + n));
        expect(pageLabels(out), [
          for (var k = 0; k < c.length; k++)
            ...labelsFor(List.generate(c[k], (i) => i), prefix: 'F$k-')
        ]);
      });
    }
  });

  group('extract by page range text', () {
    const ranges = ['1', '8', '1-8', '2-4', '8-', '-3', '5,1,3', '2,2', '7-8,1-2', '4 6 8'];
    for (final r in ranges) {
      test('"$r" of 8', () {
        final idx = parsePageRange(r, 8);
        final out = PdfTools.extract(pdfs[8]!, idx);
        expect(pageLabels(out), labelsFor(idx));
      });
    }
  });

  group('split', () {
    for (final n in [3, 5, 8]) {
      for (final size in [1, 2, 3]) {
        test('$n pages into files of $size', () {
          final groups = fixedGroups(n, size);
          final parts = splitJob((pdfs[n]!, groups));
          expect(parts.length, groups.length);
          for (var k = 0; k < parts.length; k++) {
            expect(pageLabels(parts[k]), labelsFor(groups[k]));
          }
        });
      }
    }
    for (final s in ['1-2, 3-5', '5, 4, 3', '1, 1-2', '2-, -1']) {
      test('split groups "$s"', () {
        final groups = parseSplitGroups(s, 5);
        final parts = PdfTools.split(pdfs[5]!, groups);
        expect([for (final p in parts) pageLabels(p)],
            [for (final g in groups) labelsFor(g)]);
      });
    }
  });

  group('removePages', () {
    final cases = <Set<int>>[{0}, {4}, {1, 3}, {0, 2, 4}, {7}, {9}, {}];
    for (final rm in cases) {
      test('remove $rm from 5', () {
        final out = PdfTools.removePages(pdfs[5]!, rm);
        final keep = [for (var i = 0; i < 5; i++) if (!rm.contains(i)) i];
        expect(pageLabels(out), labelsFor(keep));
      });
    }
    test('removing every page is refused', () {
      expect(() => PdfTools.removePages(pdfs[2]!, {0, 1}), throwsArgumentError);
    });
  });

  group('organize with seeded orders', () {
    for (var seed = 0; seed < 20; seed++) {
      test('seed $seed', () {
        final r = Random(seed);
        final n = [1, 2, 3, 5, 8][r.nextInt(5)];
        final refs = [
          for (var k = 0; k < 1 + r.nextInt(8); k++) PageRef(r.nextInt(n), r.nextInt(4))
        ];
        final out = organizeJob((pdfs[n]!, refs));
        expect(pageLabels(out), labelsFor(refs.map((p) => p.index)));
        for (var k = 0; k < refs.length; k++) {
          final s = PdfTools.pageSize(out, k);
          final landscape = refs[k].quarterTurns.isOdd;
          expect(s.width > s.height, landscape, reason: 'page $k ${refs[k].quarterTurns}');
        }
      });
    }
  });

  group('rotate', () {
    for (final turns in [0, 1, 2, 3, 4, 5, -1]) {
      test('all pages by $turns quarter turns', () {
        final out = rotateJob((pdfs[3]!, turns));
        final odd = (turns % 4).isOdd;
        for (var i = 0; i < 3; i++) {
          final s = PdfTools.pageSize(out, i);
          expect(s.width, odd ? 842 : 595);
          expect(s.height, odd ? 595 : 842);
        }
        expect(pageLabels(out), labelsFor([0, 1, 2]));
      });
    }
    for (final sel in [<int>{0}, <int>{1, 2}, <int>{}]) {
      test('only pages $sel', () {
        final out = PdfTools.rotate(pdfs[3]!, 1, pages: sel);
        for (var i = 0; i < 3; i++) {
          expect(PdfTools.pageSize(out, i).width, sel.contains(i) ? 842 : 595);
        }
      });
    }
    test('landscape source turned once becomes portrait', () {
      final land = labelledPdf(1, size: const Size(842, 595));
      final s = PdfTools.pageSize(PdfTools.rotate(land, 1), 0);
      expect(s.width, lessThan(s.height));
    });
  });

  group('crop', () {
    const cases = [
      (0.0, 0.0, 0.0, 0.0),
      (0.1, 0.0, 0.0, 0.0),
      (0.0, 0.1, 0.0, 0.0),
      (0.0, 0.0, 0.2, 0.0),
      (0.0, 0.0, 0.0, 0.25),
      (0.1, 0.1, 0.1, 0.1),
      (0.05, 0.2, 0.15, 0.3),
      (0.3, 0.0, 0.3, 0.0),
    ];
    for (final (l, t, r, b) in cases) {
      test('l=$l t=$t r=$r b=$b', () {
        final out = cropJob((pdfs[2]!, l, t, r, b));
        expect(PdfTools.pageCount(out), 2);
        for (var i = 0; i < 2; i++) {
          final s = PdfTools.pageSize(out, i);
          expect(s.width, closeTo(595 * (1 - l - r), 1));
          expect(s.height, closeTo(842 * (1 - t - b), 1));
        }
      });
    }
  });

  group('page labels', () {
    const cases = <(int, int, String, String)>[
      (1, 1, '{n} / {total}', '1 / 1'),
      (3, 9, '{n} / {total}', '3 / 9'),
      (12, 40, 'Page {n} of {total}', 'Page 12 of 40'),
      (5, 5, '{n}', '5'),
      (2, 7, '- {n} -', '- 2 -'),
      (4, 8, 'no placeholders', 'no placeholders'),
      (6, 6, '{n}{n}', '66'),
      (1, 10, '{total}', '10'),
    ];
    for (final (n, total, pattern, want) in cases) {
      test('"$pattern" for $n/$total', () {
        expect(PdfTools.pageLabel(n, total, pattern), want);
      });
    }
  });

  group('page numbers', () {
    for (final pos in PageNumberPosition.values) {
      for (final n in [1, 3]) {
        test('${pos.name} on $n pages', () {
          final out = pageNumbersJob((pdfs[n]!, pos, '#{n}/{total}'));
          final t = PdfTools.pageTexts(out);
          expect(t.length, n);
          for (var i = 0; i < n; i++) {
            expect(t[i], contains('#${i + 1}/$n'));
          }
        });
      }
    }
    test('startAt shifts the numbers', () {
      final out = PdfTools.addPageNumbers(pdfs[2]!, pattern: 'p{n}of{total}', startAt: 10);
      final t = PdfTools.pageTexts(out);
      expect(t[0], contains('p10of11'));
      expect(t[1], contains('p11of11'));
    });
  });

  group('watermark', () {
    for (final text in ['DRAFT', 'CONFIDENTIAL', 'Copy 2']) {
      for (final opacity in [0.1, 0.5, 1.0]) {
        test('"$text" at $opacity', () {
          final out = watermarkJob((pdfs[2]!, text, opacity));
          final t = PdfTools.pageTexts(out);
          expect(t.length, 2);
          expect(t.every((p) => p.contains(text)), isTrue);
          expect(t[1], contains('Page 2'));
        });
      }
    }
  });

  group('protect and unlock', () {
    for (final pw in ['a', 'secret', 'p@ss w0rd', '₹rupee', '1234567890123456789012345']) {
      test('password "$pw"', () {
        final locked = protectJob((pdfs[2]!, pw));
        expect(PdfTools.isEncrypted(locked), isTrue);
        expect(() => PdfTools.pageCount(locked), throwsA(isA<PasswordRequired>()));
        expect(PdfTools.pageCount(locked, password: pw), 2);
        expect(() => unlockJob((locked, '${pw}x')), throwsA(isA<PasswordRequired>()));
        final open = unlockJob((locked, pw));
        expect(PdfTools.isEncrypted(open), isFalse);
        expect(pageLabels(open), labelsFor([0, 1]));
      });
    }
    test('plain PDFs are not encrypted', () {
      expect(PdfTools.isEncrypted(pdfs[1]!), isFalse);
    });
    test('PasswordRequired has a friendly message', () {
      expect(const PasswordRequired().toString(), 'This PDF is password protected.');
    });
  });

  group('stamp, add text and cover on every page', () {
    final png = Uint8List.fromList(img.encodePng(
        img.fill(img.Image(width: 30, height: 10), color: img.ColorRgb8(0, 0, 255))));
    for (var page = 0; page < 3; page++) {
      test('stamp image on page ${page + 1}', () {
        final out = stampJob((pdfs[3]!, png, page, const Rect.fromLTWH(0.5, 0.5, 0.2, 0.1)));
        expect(pageLabels(out), labelsFor([0, 1, 2]));
      });
      test('add text on page ${page + 1}', () {
        final out = addTextJob((pdfs[3]!, 'Note$page', page, const Offset(0.2, 0.7), 12.0, 0xFF112233));
        final t = PdfTools.pageTexts(out);
        for (var i = 0; i < 3; i++) {
          expect(t[i].contains('Note$page'), i == page);
        }
      });
    }
    test('cover boxes on several pages', () {
      final out = coverJob((
        pdfs[3]!,
        {
          0: [const Rect.fromLTWH(0, 0, 0.1, 0.1)],
          2: [const Rect.fromLTWH(0.5, 0.5, 0.2, 0.2), const Rect.fromLTWH(0, 0.9, 1, 0.1)],
        }
      ));
      expect(PdfTools.pageCount(out), 3);
    });
  });

  group('optimize and text', () {
    for (final n in [1, 3, 8]) {
      test('optimize keeps $n pages of text', () {
        final out = optimizeJob(pdfs[n]!);
        expect(pageLabels(out), labelsFor(List.generate(n, (i) => i)));
        expect(textJob(out).length, n);
      });
    }
  });

  group('replaceWithImages', () {
    final jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 60)));
    for (final which in [<int>{}, {0}, {1}, {0, 2}, {0, 1, 2}]) {
      test('replace pages $which', () {
        final out = replaceJob((pdfs[3]!, {for (final i in which) i: jpg}));
        final t = pageLabels(out);
        expect(t.length, 3);
        for (var i = 0; i < 3; i++) {
          expect(t[i], which.contains(i) ? '' : 'Page ${i + 1}');
        }
      });
    }
  });

  group('PageRef', () {
    for (var start = 0; start < 4; start++) {
      for (final by in [1, 2, 3, 4, 5]) {
        test('$start turned by $by', () {
          final p = PageRef(7, start).turned(by);
          expect(p.index, 7);
          expect(p.quarterTurns, (start + by) % 4);
        });
      }
    }
    test('defaults to no turn', () => expect(const PageRef(2).quarterTurns, 0));
  });
}
