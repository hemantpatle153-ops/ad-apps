import 'dart:math';

import 'package:doc_scanner/text_diff.dart';
import 'package:flutter_test/flutter_test.dart';

const vocab = [
  'the', 'invoice', 'total', 'rupees', 'pay', 'by', 'Monday', 'Friday',
  'tax', 'GST', '18%', 'amount', 'due', 'date', 'name', 'address', 'a', 'b',
];

List<String> words(Random r, int n, int vocabSize) =>
    [for (var i = 0; i < n; i++) vocab[r.nextInt(vocabSize)]];

/// Random edit of [src]: deletes, inserts and replaces some words.
List<String> mutate(Random r, List<String> src, int vocabSize) {
  final out = <String>[];
  for (final w in src) {
    final k = r.nextInt(10);
    if (k == 0) continue; // delete
    if (k == 1) out.add(vocab[r.nextInt(vocabSize)]); // insert before
    out.add(k == 2 ? vocab[r.nextInt(vocabSize)] : w);
  }
  if (r.nextBool()) out.add(vocab[r.nextInt(vocabSize)]);
  return out;
}

int lcs(List<String> a, List<String> b) {
  var prev = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : max(prev[j], cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

List<String> side(DiffSummary d, DiffOp skip) => [
      for (final p in d.parts)
        if (p.op != skip) ...p.text.split(' ')
    ];

String joinWithRandomSpace(Random r, List<String> w) {
  final b = StringBuffer(r.nextBool() ? '  ' : '');
  for (var i = 0; i < w.length; i++) {
    if (i > 0) b.write([' ', '  ', '\n', '\t', ' \n '][r.nextInt(5)]);
    b.write(w[i]);
  }
  return b.toString();
}

void checkInvariants(DiffSummary d, List<String> a, List<String> b) {
  // Applying the diff reproduces both sides.
  expect(side(d, DiffOp.added), a, reason: 'old side');
  expect(side(d, DiffOp.removed), b, reason: 'new side');
  // Counts agree with the parts.
  int count(DiffOp op) => d.parts
      .where((p) => p.op == op)
      .fold(0, (s, p) => s + p.text.split(' ').length);
  expect(d.added, count(DiffOp.added));
  expect(d.removed, count(DiffOp.removed));
  expect(d.same, count(DiffOp.same));
  expect(d.same + d.removed, a.length);
  expect(d.same + d.added, b.length);
  // Matching is a longest common subsequence.
  expect(d.same, lcs(a, b));
  // Adjacent parts never share an op, and no part is empty.
  for (var i = 1; i < d.parts.length; i++) {
    expect(d.parts[i].op, isNot(d.parts[i - 1].op));
  }
  expect(d.parts.every((p) => p.text.isNotEmpty), isTrue);
  expect(d.similarity, inInclusiveRange(0.0, 1.0));
  expect(d.identical, a.join(' ') == b.join(' '));
}

void main() {
  group('tokenize', () {
    const cases = {
      '': <String>[],
      '   ': <String>[],
      'one': ['one'],
      ' a  b ': ['a', 'b'],
      'a\nb\tc': ['a', 'b', 'c'],
      'Tom & Jerry': ['Tom', '&', 'Jerry'],
      'x,y z.': ['x,y', 'z.'],
      '\n\n line \r\n two': ['line', 'two'],
    };
    cases.forEach((input, want) {
      test('"${input.replaceAll('\n', r'\n').replaceAll('\t', r'\t').replaceAll('\r', r'\r')}"',
          () => expect(tokenize(input), want));
    });
  });

  group('seeded edits keep diff invariants', () {
    for (var seed = 0; seed < 120; seed++) {
      test('seed $seed', () {
        final r = Random(seed);
        final vs = 2 + r.nextInt(vocab.length - 1);
        final a = words(r, r.nextInt(40), vs);
        final b = mutate(r, a, vs);
        final d = diffWords(joinWithRandomSpace(r, a), joinWithRandomSpace(r, b));
        checkInvariants(d, a, b);
      });
    }
  });

  group('unrelated random texts keep diff invariants', () {
    for (var seed = 0; seed < 50; seed++) {
      test('seed $seed', () {
        final r = Random(1000 + seed);
        final vs = 2 + r.nextInt(8);
        final a = words(r, r.nextInt(25), vs);
        final b = words(r, r.nextInt(25), vs);
        checkInvariants(diffWords(a.join(' '), b.join(' ')), a, b);
      });
    }
  });

  group('symmetry', () {
    for (var seed = 0; seed < 30; seed++) {
      test('swapping sides swaps added and removed (seed $seed)', () {
        final r = Random(5000 + seed);
        final a = words(r, r.nextInt(30), 6);
        final b = mutate(r, a, 6);
        final ab = diffWords(a.join(' '), b.join(' '));
        final ba = diffWords(b.join(' '), a.join(' '));
        expect(ba.added, ab.removed);
        expect(ba.removed, ab.added);
        expect(ba.same, ab.same);
        expect(ba.similarity, closeTo(ab.similarity, 1e-12));
      });
    }
  });

  group('self diff is identical', () {
    for (var seed = 0; seed < 20; seed++) {
      test('seed $seed', () {
        final r = Random(9000 + seed);
        final a = words(r, 1 + r.nextInt(50), vocab.length);
        final d = diffWords(a.join(' '), joinWithRandomSpace(r, a));
        expect(d.identical, isTrue);
        expect(d.similarity, 1);
        expect(d.parts, [DiffPart(DiffOp.same, a.join(' '))]);
      });
    }
  });

  group('only additions or only removals', () {
    for (var n = 1; n <= 10; n++) {
      test('$n words added to empty', () {
        final b = [for (var i = 0; i < n; i++) 'w$i'];
        final d = diffWords('', b.join(' '));
        expect(d.parts, [DiffPart(DiffOp.added, b.join(' '))]);
        expect(d.similarity, 0);
      });
      test('$n words removed to empty', () {
        final a = [for (var i = 0; i < n; i++) 'w$i'];
        final d = diffWords(a.join(' '), '');
        expect(d.parts, [DiffPart(DiffOp.removed, a.join(' '))]);
        expect(d.removed, n);
        expect(d.identical, isFalse);
      });
    }
  });

  group('similarity values', () {
    const cases = <(String, String, double)>[
      ('a b c d', 'a b c d', 1),
      ('a b c d', 'a b c', 0.75),
      ('a b', 'a b c d', 0.5),
      ('a', 'b', 0),
      ('a b c d e', 'a x c y e', 0.6),
      ('', 'x', 0),
      ('x y', 'y x', 0.5),
      ('a a a a', 'a', 0.25),
    ];
    for (final (a, b, s) in cases) {
      test('"$a" vs "$b" is $s', () {
        expect(diffWords(a, b).similarity, closeTo(s, 1e-9));
      });
    }
  });

  group('large inputs', () {
    for (final n in [500, 2000, 6000]) {
      test('$n words with an edit in the middle', () {
        final a = List.generate(n, (i) => 'w$i');
        final b = [...a]..[n ~/ 2] = 'X';
        final d = diffWords(a.join(' '), b.join(' '));
        expect([d.added, d.removed, d.same], [1, 1, n - 1]);
        expect(side(d, DiffOp.removed), b);
      });
    }
    test('very different large middles fall back to replace', () {
      final a = List.generate(2500, (i) => 'a$i');
      final b = List.generate(2500, (i) => 'b$i');
      final d = diffWords(a.join(' '), b.join(' '));
      expect(d.parts, [
        DiffPart(DiffOp.removed, a.join(' ')),
        DiffPart(DiffOp.added, b.join(' ')),
      ]);
      expect(side(d, DiffOp.added), a);
    });
  });

  group('DiffPart', () {
    test('equality and hash use op and text', () {
      const p = DiffPart(DiffOp.same, 'x');
      expect(p, const DiffPart(DiffOp.same, 'x'));
      expect(p.hashCode, const DiffPart(DiffOp.same, 'x').hashCode);
      expect(p, isNot(const DiffPart(DiffOp.added, 'x')));
      expect(p, isNot(const DiffPart(DiffOp.same, 'y')));
    });
    for (final op in DiffOp.values) {
      test('toString for ${op.name}', () {
        expect(DiffPart(op, 'hi').toString(), '${op.name}:"hi"');
      });
    }
  });
}
