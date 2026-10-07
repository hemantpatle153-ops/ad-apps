import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/streak.dart';

Set<Day> days(Day today, List<int> offsets) =>
    {for (final o in offsets) today.addDays(o)};

void main() {
  final today = Day(2026, 10, 7);

  group('StreakInfo.compute table', () {
    // offsets relative to today -> (current, best, playedToday)
    final cases = <(String, List<int>, int, int, bool)>[
      ('nothing played', [], 0, 0, false),
      ('only today', [0], 1, 1, true),
      ('only yesterday (alive, at risk)', [-1], 1, 1, false),
      ('only two days ago (lost)', [-2], 0, 1, false),
      ('today and yesterday', [0, -1], 2, 2, true),
      ('three in a row up to yesterday', [-1, -2, -3], 3, 3, false),
      ('gap yesterday breaks it', [0, -2, -3], 1, 2, true),
      ('long old streak, new short one', [0, -1, -5, -6, -7, -8], 2, 4, true),
      ('30 days in a row', List.generate(30, (i) => -i), 30, 30, true),
      ('30 days ending yesterday', List.generate(30, (i) => -i - 1), 30, 30, false),
      ('every other day', [0, -2, -4, -6], 1, 1, true),
      ('future days ignored', [1, 2, 3], 0, 0, false),
      ('future plus today', [1, 0, -1], 2, 2, true),
      ('duplicates collapse', [0, 0, -1, -1], 2, 2, true),
      ('best in the distant past', [-100, -101, -102, -103, -104, 0], 1, 5, true),
    ];
    for (final (name, offs, cur, best, played) in cases) {
      test(name, () {
        final st = StreakInfo.compute(days(today, offs), today);
        expect(st.current, cur, reason: 'current');
        expect(st.best, best, reason: 'best');
        expect(st.playedToday, played, reason: 'playedToday');
        expect(st.atRisk, !played && cur > 0, reason: 'atRisk');
      });
    }
  });

  group('streak over consecutive days of play', () {
    // Simulate a player who plays every day for 60 days from many start
    // dates, including month and year ends and leap days.
    final starts = [
      Day(2026, 1, 1), Day(2026, 2, 27), Day(2024, 2, 27), Day(2026, 3, 28),
      Day(2026, 10, 25), Day(2026, 12, 15), Day(2027, 12, 31), Day(2028, 2, 28),
    ];
    for (final start in starts) {
      test('daily play from $start grows by one each day', () {
        final played = <Day>{};
        for (var i = 0; i < 60; i++) {
          final d = start.addDays(i);
          final before = StreakInfo.compute(played, d);
          expect(before.current, i, reason: 'before playing on $d');
          expect(before.atRisk, i > 0);
          played.add(d);
          final after = StreakInfo.compute(played, d);
          expect(after.current, i + 1);
          expect(after.best, i + 1);
          expect(after.playedToday, isTrue);
        }
      });
    }
  });

  group('missed days', () {
    for (var missed = 1; missed <= 10; missed++) {
      test('missing $missed day(s) resets the streak, keeps best', () {
        final played = days(today, List.generate(5, (i) => -i - missed - 1));
        final st = StreakInfo.compute(played, today);
        expect(st.best, 5);
        expect(st.current, 0);
        expect(st.atRisk, isFalse);
      });
    }
  });

  group('IST day boundaries', () {
    // A quiz finished at 23:59 IST and the next at 00:01 IST are on
    // consecutive days, whatever the phone's timezone.
    final pairs = <(DateTime, DateTime)>[
      (DateTime.utc(2026, 10, 6, 18, 29), DateTime.utc(2026, 10, 6, 18, 31)),
      (DateTime.utc(2026, 12, 31, 18, 29), DateTime.utc(2026, 12, 31, 18, 31)),
      (DateTime.utc(2026, 3, 28, 18, 29), DateTime.utc(2026, 3, 28, 18, 31)),
      (DateTime.utc(2026, 11, 1, 18, 29), DateTime.utc(2026, 11, 1, 18, 31)),
    ];
    for (final (a, b) in pairs) {
      test('$a then $b count as two days', () {
        final played = {Day.ist(a), Day.ist(b)};
        final st = StreakInfo.compute(played, Day.ist(b));
        expect(st.current, 2);
      });
    }
    test('two quizzes on the same IST day count once', () {
      final a = DateTime.utc(2026, 10, 6, 18, 31); // 00:01 IST
      final b = DateTime.utc(2026, 10, 7, 18, 29); // 23:59 IST
      final st = StreakInfo.compute({Day.ist(a), Day.ist(b)}, Day.ist(b));
      expect(st.current, 1);
      expect(st.totalDays, 1);
    });
  });

  group('heatLevel', () {
    final cases = <(double, int)>[
      (0, 1), (0.1, 1), (0.24, 1), (0.25, 2), (0.49, 2), (0.5, 3),
      (0.79, 3), (0.8, 4), (1.0, 4), (double.nan, 1), (-1, 1),
    ];
    for (final (f, level) in cases) {
      test('$f -> $level', () => expect(heatLevel(f), level));
    }
  });

  group('heatmapWeeks', () {
    test('ends with the week of today, Monday first', () {
      final weeks = heatmapWeeks(today, 15, {});
      expect(weeks.length, 15);
      for (final w in weeks) {
        expect(w.length, 7);
        expect(w.first.day.weekday, DateTime.monday);
        expect(w.last.day.weekday, DateTime.sunday);
      }
      final last = weeks.last;
      expect(last.any((c) => c.day == today), isTrue);
      expect(last.where((c) => c.future).map((c) => c.day),
          [today.addDays(1), today.addDays(2), today.addDays(3), today.addDays(4)]);
    });
    test('consecutive days without gaps', () {
      final cells = heatmapWeeks(today, 10, {}).expand((w) => w).toList();
      for (var i = 1; i < cells.length; i++) {
        expect(cells[i].day.difference(cells[i - 1].day), 1);
      }
    });
    test('levels follow scores', () {
      final weeks = heatmapWeeks(today, 2, {today: 1.0, today.addDays(-1): 0.3});
      final cells = weeks.expand((w) => w).toList();
      expect(cells.firstWhere((c) => c.day == today).level, 4);
      expect(cells.firstWhere((c) => c.day == today.addDays(-1)).level, 2);
      expect(cells.firstWhere((c) => c.day == today.addDays(-2)).level, 0);
    });
    for (var wd = 0; wd < 7; wd++) {
      test('works when today is weekday ${wd + 1}', () {
        final t = Day(2026, 10, 5).addDays(wd);
        final weeks = heatmapWeeks(t, 4, {});
        expect(weeks.last.where((c) => !c.future).last.day, t);
      });
    }
  });
}
