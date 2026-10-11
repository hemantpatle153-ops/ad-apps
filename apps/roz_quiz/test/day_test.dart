import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/day.dart';

void main() {
  group('Day.tryParse', () {
    const valid = {
      '2026-10-07': (2026, 10, 7),
      '2024-02-29': (2024, 2, 29),
      '2000-02-29': (2000, 2, 29),
      '1999-12-31': (1999, 12, 31),
      '2026-01-01': (2026, 1, 1),
      ' 2026-10-07 ': (2026, 10, 7),
    };
    for (final e in valid.entries) {
      test('parses "${e.key}"', () {
        final d = Day.tryParse(e.key)!;
        expect((d.year, d.month, d.day), e.value);
      });
    }
    const invalid = [
      '2026-02-29', // not a leap year
      '1900-02-29', // century, not leap
      '2026-02-30',
      '2026-04-31',
      '2026-13-01',
      '2026-00-10',
      '2026-10-00',
      '2026-10-32',
      '26-10-07',
      '2026/10/07',
      '2026-1-7',
      '2026-10-07T00:00:00Z',
      '',
      'today',
    ];
    for (final s in invalid) {
      test('rejects "$s"', () => expect(Day.tryParse(s), isNull));
    }
    test('rejects non-strings', () {
      expect(Day.tryParse(null), isNull);
      expect(Day.tryParse(20261007), isNull);
      expect(Day.tryParse(['2026-10-07']), isNull);
    });
  });

  group('Day.ist conversion', () {
    // UTC instant -> IST calendar day. IST = UTC+05:30.
    final cases = <(DateTime, String)>[
      (DateTime.utc(2026, 10, 6, 18, 29, 59), '2026-10-06'),
      (DateTime.utc(2026, 10, 6, 18, 30), '2026-10-07'),
      (DateTime.utc(2026, 10, 7, 0, 0), '2026-10-07'),
      (DateTime.utc(2026, 10, 7, 18, 29), '2026-10-07'),
      (DateTime.utc(2026, 10, 7, 18, 30), '2026-10-08'),
      (DateTime.utc(2026, 12, 31, 18, 30), '2027-01-01'),
      (DateTime.utc(2026, 12, 31, 18, 29), '2026-12-31'),
      (DateTime.utc(2024, 2, 28, 18, 30), '2024-02-29'),
      (DateTime.utc(2024, 2, 29, 18, 30), '2024-03-01'),
      (DateTime.utc(2026, 3, 29, 1, 0), '2026-03-29'), // EU DST switch
      (DateTime.utc(2026, 3, 8, 7, 0), '2026-03-08'), // US DST switch
      (DateTime.utc(2026, 11, 1, 6, 0), '2026-11-01'), // US DST end
    ];
    for (final (t, key) in cases) {
      test('$t is $key in IST', () => expect(Day.ist(t).key, key));
    }

    test('a local DateTime is converted through UTC', () {
      final local = DateTime.utc(2026, 10, 6, 20).toLocal();
      expect(Day.ist(local).key, '2026-10-07');
    });

    // Every 30 minutes over a year: the IST day must change exactly at
    // 18:30 UTC and never skip or repeat.
    test('changes exactly once per day at 18:30 UTC for a whole year', () {
      var t = DateTime.utc(2026, 1, 1, 0, 0);
      var prev = Day.ist(t);
      var changes = 0;
      while (t.isBefore(DateTime.utc(2027, 1, 1))) {
        t = t.add(const Duration(minutes: 30));
        final d = Day.ist(t);
        if (d != prev) {
          changes++;
          expect(d.difference(prev), 1);
          expect((t.hour, t.minute), (18, 30));
        }
        prev = d;
      }
      expect(changes, 365);
    });
  });

  group('Day arithmetic', () {
    test('index of the epoch is 0', () => expect(Day(1970, 1, 1).index, 0));
    test('fromIndex reverses index', () {
      for (var i = -800; i <= 30000; i += 37) {
        expect(Day.fromIndex(i).index, i);
      }
    });
    final adds = <(String, int, String)>[
      ('2026-10-07', 1, '2026-10-08'),
      ('2026-10-31', 1, '2026-11-01'),
      ('2026-12-31', 1, '2027-01-01'),
      ('2024-02-28', 1, '2024-02-29'),
      ('2025-02-28', 1, '2025-03-01'),
      ('2026-03-01', -1, '2026-02-28'),
      ('2024-03-01', -1, '2024-02-29'),
      ('2026-01-01', -1, '2025-12-31'),
      ('2026-10-07', 365, '2027-10-07'),
      ('2026-10-07', -7, '2026-09-30'),
      ('2026-10-07', 0, '2026-10-07'),
    ];
    for (final (from, n, to) in adds) {
      test('$from + $n = $to', () {
        final a = Day.tryParse(from)!;
        expect(a.addDays(n).key, to);
        expect(a.addDays(n).difference(a), n);
      });
    }
    test('normalises overflowing dates', () {
      expect(Day(2026, 1, 32).key, '2026-02-01');
      expect(Day(2026, 13, 1).key, '2027-01-01');
      expect(Day(2026, 3, 0).key, '2026-02-28');
    });
    final weekdays = {
      '2026-10-05': DateTime.monday,
      '2026-10-07': DateTime.wednesday,
      '2026-10-11': DateTime.sunday,
      '2024-02-29': DateTime.thursday,
      '2000-01-01': DateTime.saturday,
    };
    for (final e in weekdays.entries) {
      test('${e.key} weekday', () => expect(Day.tryParse(e.key)!.weekday, e.value));
    }
    test('startUtc is IST midnight', () {
      expect(Day(2026, 10, 7).startUtc, DateTime.utc(2026, 10, 6, 18, 30));
      expect(Day.ist(Day(2026, 10, 7).startUtc), Day(2026, 10, 7));
      expect(Day.ist(Day(2026, 10, 7).startUtc.subtract(const Duration(seconds: 1))),
          Day(2026, 10, 6));
    });
    test('atIst adds minutes after IST midnight', () {
      expect(Day(2026, 10, 7).atIst(8 * 60), DateTime.utc(2026, 10, 7, 2, 30));
      expect(Day(2026, 10, 7).atIst(20 * 60), DateTime.utc(2026, 10, 7, 14, 30));
      expect(Day(2026, 10, 7).atIst(0), DateTime.utc(2026, 10, 6, 18, 30));
    });
    test('equality, hash and ordering', () {
      final a = Day(2026, 10, 7), b = Day.tryParse('2026-10-07')!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a, b}.length, 1);
      expect(a.compareTo(a.addDays(1)), lessThan(0));
      expect(a.isBefore(a.addDays(1)), isTrue);
      expect(a.isAfter(a.addDays(-1)), isTrue);
      expect(a.toString(), '2026-10-07');
    });
    test('key pads years, months and days', () {
      expect(Day(987, 3, 4).key, '0987-03-04');
    });
    test('key round-trips for 10 years of days', () {
      var d = Day(2020, 1, 1);
      for (var i = 0; i < 3653; i++) {
        expect(Day.tryParse(d.key), d);
        d = d.addDays(1);
      }
    });
  });
}
