import 'dart:math';

import 'package:doc_scanner/page_ranges.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> span(int from, int to) => [for (var p = from; p <= to; p++) p - 1];

void main() {
  group('single page numbers', () {
    for (final n in [1, 2, 5, 12, 40]) {
      for (var p = 1; p <= n; p += (n > 12 ? 7 : 1)) {
        test('page $p of $n', () {
          expect(parsePageRange('$p', n), [p - 1]);
        });
      }
    }
  });

  group('closed ranges', () {
    for (final n in [3, 8, 20]) {
      for (var a = 1; a <= n; a += (n > 8 ? 4 : 1)) {
        for (var b = a; b <= n; b += (n > 8 ? 5 : 2)) {
          test('$a-$b of $n', () {
            expect(parsePageRange('$a-$b', n), span(a, b));
          });
        }
      }
    }
  });

  group('open ended ranges', () {
    for (final n in [1, 4, 9, 30]) {
      for (final p in {1, (n + 1) ~/ 2, n}) {
        test('$p- of $n runs to the end', () {
          expect(parsePageRange('$p-', n), span(p, n));
        });
        test('-$p of $n starts at page 1', () {
          expect(parsePageRange('-$p', n), span(1, p));
        });
      }
      test('bare dash of $n is every page', () {
        expect(parsePageRange('-', n), span(1, n));
      });
    }
  });

  group('separators', () {
    const cases = {
      '1,2,3': [0, 1, 2],
      '1, 2, 3': [0, 1, 2],
      '1;2;3': [0, 1, 2],
      '1 2 3': [0, 1, 2],
      '1\t2\n3': [0, 1, 2],
      ',,1,,3,,': [0, 2],
      ' ; 4 ; ': [3],
      '1-2;5-6': [0, 1, 4, 5],
      '2-3 , 1': [1, 2, 0],
      '6,5,4': [5, 4, 3],
      '1,1,1': [0, 0, 0],
      '1-3,2-4': [0, 1, 2, 1, 2, 3],
      '007': [6],
      '01-03': [0, 1, 2],
      '10': [9],
      '9-10': [8, 9],
      '+2': [1],
    };
    cases.forEach((input, want) {
      test('"${input.replaceAll('\n', r'\n').replaceAll('\t', r'\t')}"', () {
        expect(parsePageRange(input, 10), want);
      });
    });
  });

  group('rejected input', () {
    const bad = {
      '0': 5,
      '6': 5,
      '100': 5,
      '0-2': 5,
      '2-6': 5,
      '4-2': 5,
      '6-': 5,
      '-6': 5,
      'abc': 5,
      'one': 5,
      '1.5': 5,
      '1-2-3': 5,
      '1--2': 5,
      '#3': 5,
      '3a': 5,
      '': 5,
      ' ': 5,
      ',,,': 5,
      ';': 5,
      '1,x': 5,
      '2,9': 5,
      '1': 0,
      '-': 0,
    };
    bad.forEach((input, n) {
      test('"$input" with $n pages throws', () {
        expect(() => parsePageRange(input, n), throwsFormatException);
      });
    });
  });

  group('error messages', () {
    test('empty asks for page numbers', () {
      expect(
          () => parsePageRange('', 3),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', 'Enter page numbers.')));
    });
    for (final s in ['x', 'p2', '?']) {
      test('"$s" names the bad part', () {
        expect(
            () => parsePageRange(s, 3),
            throwsA(isA<FormatException>().having((e) => e.message, 'message',
                '"$s" is not a page number.')));
      });
    }
    for (final s in ['0', '4', '2-9', '3-1']) {
      test('"$s" names the page bounds', () {
        expect(
            () => parsePageRange(s, 3),
            throwsA(isA<FormatException>().having((e) => e.message, 'message',
                '"$s" is outside pages 1 to 3.')));
      });
    }
  });

  group('seeded random range lists', () {
    for (var seed = 0; seed < 60; seed++) {
      test('seed $seed matches a reference expansion', () {
        final r = Random(seed);
        final n = 1 + r.nextInt(50);
        final parts = <String>[];
        final want = <int>[];
        for (var k = 0; k < 1 + r.nextInt(6); k++) {
          final a = 1 + r.nextInt(n);
          final b = a + r.nextInt(n - a + 1);
          switch (r.nextInt(4)) {
            case 0:
              parts.add('$a');
              want.add(a - 1);
            case 1:
              parts.add('$a-$b');
              want.addAll(span(a, b));
            case 2:
              parts.add('$a-');
              want.addAll(span(a, n));
            default:
              parts.add('-$b');
              want.addAll(span(1, b));
          }
        }
        final sep = [',', ', ', ';', ' '][r.nextInt(4)];
        final got = parsePageRange(parts.join(sep), n);
        expect(got, want);
        expect(got.every((i) => i >= 0 && i < n), isTrue);
      });
    }
  });

  group('split groups', () {
    const cases = <String, List<List<int>>>{
      '1': [
        [0]
      ],
      '1-2, 3': [
        [0, 1],
        [2]
      ],
      '1 3, 5': [
        [0, 2],
        [4]
      ],
      '6-, -1': [
        [5, 6, 7],
        [0]
      ],
      '2;3, 4': [
        [1, 2],
        [3]
      ],
      ',1,,2,': [
        [0],
        [1]
      ],
      '8,7,6': [
        [7],
        [6],
        [5]
      ],
      '1-8': [
        [0, 1, 2, 3, 4, 5, 6, 7]
      ],
    };
    cases.forEach((input, want) {
      test('"$input"', () {
        expect(parseSplitGroups(input, 8), want);
      });
    });
    test('empty input gives no groups', () {
      expect(parseSplitGroups('', 8), isEmpty);
      expect(parseSplitGroups(' , ', 8), isEmpty);
    });
    for (final s in ['9', '1, x', '0-2, 3']) {
      test('"$s" is rejected', () {
        expect(() => parseSplitGroups(s, 8), throwsFormatException);
      });
    }
  });

  group('fixed groups', () {
    for (final n in [0, 1, 2, 3, 7, 10, 16, 25]) {
      for (final size in [1, 2, 3, 5, 10, 30]) {
        test('$n pages in groups of $size', () {
          final g = fixedGroups(n, size);
          expect(g.length, (n + size - 1) ~/ size);
          expect(g.expand((e) => e).toList(), [for (var i = 0; i < n; i++) i]);
          for (var k = 0; k < g.length; k++) {
            if (k < g.length - 1) expect(g[k].length, size);
            expect(g[k].length, inInclusiveRange(1, size));
            expect(g[k].first, k * size);
          }
        });
      }
    }
    for (final size in [0, -1, -10]) {
      test('size $size is rejected', () {
        expect(() => fixedGroups(5, size), throwsFormatException);
      });
    }
  });
}
