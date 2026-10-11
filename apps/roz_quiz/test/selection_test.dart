import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/selection.dart';

import 'support/harness.dart';

List<Question> bank(int n, {String subject = 'gk', String prefix = 'b'}) => [
      for (var i = 0; i < n; i++)
        makeQ(id: '$prefix${i.toString().padLeft(3, '0')}', subject: subject)
    ];

void main() {
  group('SeededRandom', () {
    test('same seed, same sequence', () {
      final a = SeededRandom(7), b = SeededRandom(7);
      for (var i = 0; i < 100; i++) {
        expect(a.nextUint32(), b.nextUint32());
      }
    });
    test('different seeds differ', () {
      final a = SeededRandom(1), b = SeededRandom(2);
      final sa = [for (var i = 0; i < 10; i++) a.nextUint32()];
      final sb = [for (var i = 0; i < 10; i++) b.nextUint32()];
      expect(sa, isNot(sb));
    });
    test('known mulberry32 values for seed 0 (same as the JS reference)', () {
      // mulberry32(0) in JavaScript: 1144304738, 1416247, 958946056
      final r = SeededRandom(0);
      expect([r.nextUint32(), r.nextUint32(), r.nextUint32()],
          [1144304738, 1416247, 958946056]);
    });
    test('outputs are 32-bit', () {
      final r = SeededRandom(123456789);
      for (var i = 0; i < 1000; i++) {
        final v = r.nextUint32();
        expect(v, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });
    test('negative and huge seeds are masked', () {
      expect(SeededRandom(-1).nextUint32(), SeededRandom(0xFFFFFFFF).nextUint32());
      expect(SeededRandom(1 << 40).nextUint32(), SeededRandom(0).nextUint32());
    });
    for (final max in [1, 2, 3, 10, 97]) {
      test('nextInt($max) stays in range and hits every value', () {
        final r = SeededRandom(max);
        final seen = <int>{};
        for (var i = 0; i < 2000; i++) {
          final v = r.nextInt(max);
          expect(v, inInclusiveRange(0, max - 1));
          seen.add(v);
        }
        expect(seen.length, max);
      });
    }
    test('nextInt(0) throws', () => expect(() => SeededRandom(1).nextInt(0), throwsRangeError));
    test('shuffle is a permutation', () {
      final list = List.generate(50, (i) => i);
      SeededRandom(9).shuffle(list);
      expect(list.toSet(), Set.of(List.generate(50, (i) => i)));
      expect(list, isNot(List.generate(50, (i) => i)));
    });
    test('shuffle of empty and single lists', () {
      final e = <int>[];
      SeededRandom(1).shuffle(e);
      expect(e, isEmpty);
      final one = [5];
      SeededRandom(1).shuffle(one);
      expect(one, [5]);
    });
    test('shuffle is deterministic', () {
      final a = List.generate(20, (i) => i), b = List.generate(20, (i) => i);
      SeededRandom(3).shuffle(a);
      SeededRandom(3).shuffle(b);
      expect(a, b);
    });
  });

  group('dailyFallback', () {
    final b = bank(37);
    final d0 = Day(2026, 10, 7);

    test('ten questions by default', () => expect(dailyFallback(d0, b).length, 10));
    test('custom count', () => expect(dailyFallback(d0, b, count: 5).length, 5));
    test('empty bank gives nothing', () => expect(dailyFallback(d0, const []), isEmpty));
    test('small bank gives the whole bank once', () {
      final small = bank(4);
      final out = dailyFallback(d0, small);
      expect(out.length, 4);
      expect(out.map((q) => q.id).toSet().length, 4);
    });
    test('same day, same quiz', () {
      expect(dailyFallback(d0, b).map((q) => q.id), dailyFallback(d0, b).map((q) => q.id));
    });
    test('file order does not matter', () {
      final reversed = b.reversed.toList();
      expect(dailyFallback(d0, reversed).map((q) => q.id), dailyFallback(d0, b).map((q) => q.id));
    });
    test('duplicate ids in the bank are ignored', () {
      final dup = [...b, ...b.take(5)];
      expect(dailyFallback(d0, dup).map((q) => q.id), dailyFallback(d0, b).map((q) => q.id));
    });
    test('consecutive days differ', () {
      expect(dailyFallback(d0, b).map((q) => q.id),
          isNot(dailyFallback(d0.addDays(1), b).map((q) => q.id)));
    });
    test('no duplicates inside a day for many days', () {
      for (var i = -50; i < 200; i++) {
        final ids = dailyFallback(d0.addDays(i), b).map((q) => q.id).toList();
        expect(ids.toSet().length, ids.length, reason: 'day $i');
      }
    });
    test('pre-1970 days work', () {
      final old = Day(1965, 3, 1);
      expect(dailyFallback(old, b).length, 10);
    });
    test('the real bundled bank: no question repeats within a cycle', () {
      // 200 questions, 10 a day: 20 days without a repeat, when the cycle
      // boundary falls on a day boundary.
      final big = bank(200);
      final seen = <String>{};
      // Find a day that starts a cycle: (index+1e6)*10 % 200 == 0.
      var start = d0;
      while (((start.index + 1000000) * 10) % 200 != 0) {
        start = start.addDays(1);
      }
      for (var i = 0; i < 20; i++) {
        for (final q in dailyFallback(start.addDays(i), big)) {
          expect(seen.add(q.id), isTrue, reason: 'day $i repeated ${q.id}');
        }
      }
      expect(seen.length, 200);
    });
    test('across many days every question is used about equally', () {
      final counts = <String, int>{};
      for (var i = 0; i < 370; i++) {
        for (final q in dailyFallback(d0.addDays(i), b)) {
          counts[q.id] = (counts[q.id] ?? 0) + 1;
        }
      }
      expect(counts.length, 37);
      final min = counts.values.reduce((a, c) => a < c ? a : c);
      final max = counts.values.reduce((a, c) => a > c ? a : c);
      // 3700 picks over 37 questions: about 100 each. Days that cross a
      // cycle boundary may skip a duplicate, so allow a little spread.
      expect(min, greaterThanOrEqualTo(92));
      expect(max, lessThanOrEqualTo(110));
    });
  });

  group('PracticeFilter', () {
    final q = makeQ(subject: 'polity', exams: ['ssc', 'upsc'], difficulty: Difficulty.hard, asked: 'UPSC 2019');
    final plain = makeQ(subject: 'gk', exams: ['railway'], difficulty: Difficulty.easy);

    test('empty filter matches all', () {
      expect(const PracticeFilter().matches(q), isTrue);
      expect(const PracticeFilter().matches(plain), isTrue);
    });
    test('subject', () {
      expect(const PracticeFilter(subject: 'polity').matches(q), isTrue);
      expect(const PracticeFilter(subject: 'polity').matches(plain), isFalse);
    });
    test('exam', () {
      expect(const PracticeFilter(exam: 'upsc').matches(q), isTrue);
      expect(const PracticeFilter(exam: 'upsc').matches(plain), isFalse);
      expect(const PracticeFilter(exam: 'railway').matches(plain), isTrue);
    });
    test('difficulty', () {
      expect(const PracticeFilter(difficulty: Difficulty.hard).matches(q), isTrue);
      expect(const PracticeFilter(difficulty: Difficulty.hard).matches(plain), isFalse);
    });
    test('PYQ only', () {
      expect(const PracticeFilter(pyqOnly: true).matches(q), isTrue);
      expect(const PracticeFilter(pyqOnly: true).matches(plain), isFalse);
    });
    test('all together', () {
      const f = PracticeFilter(subject: 'polity', exam: 'ssc', difficulty: Difficulty.hard, pyqOnly: true);
      expect(f.matches(q), isTrue);
      expect(f.apply([q, plain]), [q]);
    });
    test('apply keeps order', () {
      final list = bank(5);
      expect(const PracticeFilter().apply(list), list);
    });
  });

  group('pickWithoutRepeats', () {
    final pool = bank(20);

    test('picks count questions not yet seen', () {
      final r = pickWithoutRepeats(pool, 5, {}, SeededRandom(1));
      expect(r.questions.length, 5);
      expect(r.recycled, isFalse);
      expect(r.seen, {for (final q in r.questions) q.id});
    });
    test('never picks seen questions while unseen ones remain', () {
      var seen = <String>{};
      final all = <String>{};
      for (var round = 0; round < 4; round++) {
        final r = pickWithoutRepeats(pool, 5, seen, SeededRandom(round));
        for (final q in r.questions) {
          expect(all.add(q.id), isTrue, reason: 'repeat of ${q.id} in round $round');
        }
        expect(r.recycled, isFalse);
        seen = r.seen;
      }
      expect(all.length, 20);
    });
    test('recycles after the pool is used up', () {
      final seen = {for (final q in pool) q.id};
      final r = pickWithoutRepeats(pool, 5, seen, SeededRandom(1));
      expect(r.recycled, isTrue);
      expect(r.questions.length, 5);
      expect(r.seen, {for (final q in r.questions) q.id});
    });
    test('partial recycle uses all unseen first', () {
      final seen = {for (final q in pool.take(17)) q.id};
      final r = pickWithoutRepeats(pool, 5, seen, SeededRandom(4));
      final ids = r.questions.map((q) => q.id).toSet();
      for (final q in pool.skip(17)) {
        expect(ids, contains(q.id));
      }
      expect(r.recycled, isTrue);
      expect(ids.length, 5);
    });
    test('seen ids outside the pool are kept', () {
      final r = pickWithoutRepeats(pool, 5, {'other-subject-1'}, SeededRandom(1));
      expect(r.seen, contains('other-subject-1'));
      final full = {for (final q in pool) q.id, 'other-subject-1'};
      final r2 = pickWithoutRepeats(pool, 3, full, SeededRandom(1));
      expect(r2.recycled, isTrue);
      expect(r2.seen, contains('other-subject-1'));
    });
    test('count larger than pool gives the whole pool', () {
      final r = pickWithoutRepeats(pool, 50, {}, SeededRandom(1));
      expect(r.questions.length, 20);
      expect(r.questions.map((q) => q.id).toSet().length, 20);
    });
    test('empty pool', () {
      final r = pickWithoutRepeats(const [], 10, {'x'}, SeededRandom(1));
      expect(r.questions, isEmpty);
      expect(r.seen, {'x'});
    });
    test('duplicates in the pool are picked once', () {
      final r = pickWithoutRepeats([...pool, ...pool], 40, {}, SeededRandom(1));
      expect(r.questions.length, 20);
    });
    test('order is random but deterministic for a seed', () {
      final a = pickWithoutRepeats(pool, 10, {}, SeededRandom(5)).questions.map((q) => q.id);
      final b = pickWithoutRepeats(pool, 10, {}, SeededRandom(5)).questions.map((q) => q.id);
      final c = pickWithoutRepeats(pool, 10, {}, SeededRandom(6)).questions.map((q) => q.id);
      expect(a, b);
      expect(a, isNot(c));
    });
    for (var seed = 0; seed < 25; seed++) {
      test('property: no duplicates in a pick (seed $seed)', () {
        final r = SeededRandom(seed);
        final n = 1 + r.nextInt(30);
        final p = bank(n, prefix: 'p$seed-');
        final seenCount = r.nextInt(n + 1);
        final seen = {for (final q in p.take(seenCount)) q.id};
        final count = 1 + r.nextInt(n + 5);
        final res = pickWithoutRepeats(p, count, seen, SeededRandom(seed * 31));
        final ids = res.questions.map((q) => q.id).toList();
        expect(ids.toSet().length, ids.length);
        expect(ids.length, count < n ? count : n);
        expect(res.recycled, n - seenCount < (count < n ? count : n));
        expect(res.seen.containsAll(ids), isTrue);
      });
    }
  });

  group('buildMockTest', () {
    final pool = [
      ...bank(10, subject: 'maths', prefix: 'm'),
      ...bank(10, subject: 'gk', prefix: 'g'),
      ...bank(10, subject: 'polity', prefix: 'p'),
      makeQ(id: 'bank-only', subject: 'gk', exams: ['banking']),
    ];
    test('sections follow the subject order', () {
      final r = buildMockTest(pool, 15, {}, SeededRandom(3), exam: 'ssc');
      final order = r.questions.map((q) => kSubjects.indexOf(q.subject)).toList();
      final sorted = [...order]..sort();
      expect(order, sorted);
      expect(r.questions.length, 15);
    });
    test('exam filter applies', () {
      final r = buildMockTest(pool, 31, {}, SeededRandom(3), exam: 'banking');
      expect(r.questions.map((q) => q.id), ['bank-only']);
    });
    test('no exam means any exam', () {
      final r = buildMockTest(pool, 100, {}, SeededRandom(3));
      expect(r.questions.length, 31);
    });
    test('no repeats across two mocks', () {
      final a = buildMockTest(pool, 15, {}, SeededRandom(3), exam: 'ssc');
      final b = buildMockTest(pool, 15, a.seen, SeededRandom(4), exam: 'ssc');
      expect(a.questions.map((q) => q.id).toSet().intersection(b.questions.map((q) => q.id).toSet()),
          isEmpty);
      expect(b.recycled, isFalse);
    });
  });
}
