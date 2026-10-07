import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/ymd.dart';

void main() {
  group('Ymd.tryParse accepts real dates', () {
    const valid = {
      '2026-10-07': (2026, 10, 7),
      '2026-01-01': (2026, 1, 1),
      '2026-12-31': (2026, 12, 31),
      '2024-02-29': (2024, 2, 29),
      '2000-02-29': (2000, 2, 29),
      '2026-04-30': (2026, 4, 30),
      '2026-06-30': (2026, 6, 30),
      '2026-09-30': (2026, 9, 30),
      '2026-11-30': (2026, 11, 30),
      '2026-03-31': (2026, 3, 31),
      '1990-05-15': (1990, 5, 15),
      ' 2026-10-07 ': (2026, 10, 7),
    };
    valid.forEach((s, ymd) {
      test('"$s"', () {
        final d = Ymd.tryParse(s)!;
        expect((d.year, d.month, d.day), ymd);
      });
    });
  });

  group('Ymd.tryParse rejects', () {
    const invalid = <Object?>[
      null,
      '',
      'tomorrow',
      '2026-02-29',
      '1900-02-29',
      '2026-02-30',
      '2026-04-31',
      '2026-13-01',
      '2026-00-10',
      '2026-10-00',
      '2026-10-32',
      '26-10-07',
      '2026/10/07',
      '07-10-2026',
      '2026-1-7',
      '2026-10-07T00:00:00Z',
      '1899-12-31',
      '2201-01-01',
      20261007,
      true,
      ['2026-10-07'],
    ];
    for (final v in invalid) {
      test('$v', () => expect(Ymd.tryParse(v), isNull));
    }
  });

  group('round trip toString', () {
    for (final s in ['2026-10-07', '2026-01-09', '1999-12-31', '2030-02-28']) {
      test(s, () => expect(Ymd.tryParse(s).toString(), s));
    }
  });

  group('addDays rolls over months and years', () {
    final cases = <(Ymd, int, String)>[
      (Ymd(2026, 10, 7), 1, '2026-10-08'),
      (Ymd(2026, 10, 31), 1, '2026-11-01'),
      (Ymd(2026, 12, 31), 1, '2027-01-01'),
      (Ymd(2026, 1, 1), -1, '2025-12-31'),
      (Ymd(2024, 2, 28), 1, '2024-02-29'),
      (Ymd(2026, 2, 28), 1, '2026-03-01'),
      (Ymd(2026, 3, 1), -1, '2026-02-28'),
      (Ymd(2024, 3, 1), -1, '2024-02-29'),
      (Ymd(2026, 11, 5), -3, '2026-11-02'),
      (Ymd(2026, 10, 2), -3, '2026-09-29'),
      (Ymd(2026, 10, 7), 365, '2027-10-07'),
      (Ymd(2026, 10, 7), 0, '2026-10-07'),
    ];
    for (final (d, n, want) in cases) {
      test('$d + $n', () => expect(d.addDays(n).toString(), want));
    }
  });

  group('daysUntil', () {
    final cases = <(String, String, int)>[
      ('2026-10-07', '2026-10-07', 0),
      ('2026-10-07', '2026-10-08', 1),
      ('2026-10-07', '2026-10-10', 3),
      ('2026-10-07', '2026-11-05', 29),
      ('2026-10-07', '2026-10-06', -1),
      ('2026-10-07', '2025-10-07', -365),
      ('2024-02-28', '2024-03-01', 2),
      ('2026-02-28', '2026-03-01', 1),
      ('2026-12-31', '2027-01-01', 1),
      ('2026-03-28', '2026-03-30', 2),
      ('2026-10-24', '2026-10-26', 2),
    ];
    for (final (a, b, n) in cases) {
      test('$a -> $b = $n', () => expect(Ymd.tryParse(a)!.daysUntil(Ymd.tryParse(b)!), n));
    }
  });

  group('comparison', () {
    test('compareTo orders by year, month, day', () {
      final list = [Ymd(2026, 10, 7), Ymd(2025, 12, 31), Ymd(2026, 1, 15), Ymd(2026, 10, 6)]..sort();
      expect(list.map((e) => '$e'), ['2025-12-31', '2026-01-15', '2026-10-06', '2026-10-07']);
    });
    test('equality and hashCode', () {
      expect(Ymd(2026, 10, 7), Ymd.tryParse('2026-10-07'));
      expect({Ymd(2026, 10, 7), Ymd(2026, 10, 7)}.length, 1);
    });
    test('isBefore / isAfter', () {
      expect(Ymd(2026, 1, 1).isBefore(Ymd(2026, 1, 2)), isTrue);
      expect(Ymd(2026, 1, 2).isAfter(Ymd(2026, 1, 1)), isTrue);
      expect(Ymd(2026, 1, 1).isAfter(Ymd(2026, 1, 1)), isFalse);
    });
    test('weekday', () {
      expect(Ymd(2026, 10, 7).weekday, DateTime.wednesday);
      expect(Ymd(2026, 10, 11).weekday, DateTime.sunday);
    });
  });

  group('leap years', () {
    const cases = {1900: false, 2000: true, 2023: false, 2024: true, 2026: false, 2028: true, 2100: false, 2400: true};
    cases.forEach((y, leap) => test('$y', () => expect(Ymd.isLeapYear(y), leap)));
    test('February length', () {
      expect(Ymd.daysInMonth(2024, 2), 29);
      expect(Ymd.daysInMonth(2026, 2), 28);
      expect(Ymd.daysInMonth(2026, 4), 30);
      expect(Ymd.daysInMonth(2026, 12), 31);
    });
  });

  group('Ymd.istOf: the India date of an instant', () {
    final cases = <(DateTime, String)>[
      (DateTime.utc(2026, 10, 7, 0, 0), '2026-10-07'),
      (DateTime.utc(2026, 10, 6, 18, 29), '2026-10-06'),
      (DateTime.utc(2026, 10, 6, 18, 30), '2026-10-07'),
      (DateTime.utc(2026, 10, 6, 18, 31), '2026-10-07'),
      (DateTime.utc(2026, 10, 7, 18, 29, 59), '2026-10-07'),
      (DateTime.utc(2026, 10, 7, 18, 30), '2026-10-08'),
      (DateTime.utc(2026, 12, 31, 18, 30), '2027-01-01'),
      (DateTime.utc(2026, 12, 31, 18, 29), '2026-12-31'),
      (DateTime.utc(2024, 2, 28, 20, 0), '2024-02-29'),
      (DateTime.utc(2026, 10, 7, 12, 0), '2026-10-07'),
    ];
    for (final (t, want) in cases) {
      test('$t', () => expect(Ymd.istOf(t).toString(), want));
    }
    test('a local DateTime is converted through UTC', () {
      final t = DateTime.utc(2026, 10, 6, 19, 0).toLocal();
      expect(Ymd.istOf(t).toString(), '2026-10-07');
    });
  });

  group('istInstant', () {
    final cases = <(Ymd, int, int, DateTime)>[
      (Ymd(2026, 11, 2), 9, 0, DateTime.utc(2026, 11, 2, 3, 30)),
      (Ymd(2026, 11, 2), 0, 0, DateTime.utc(2026, 11, 1, 18, 30)),
      (Ymd(2026, 11, 2), 5, 29, DateTime.utc(2026, 11, 1, 23, 59)),
      (Ymd(2026, 11, 2), 5, 30, DateTime.utc(2026, 11, 2, 0, 0)),
      (Ymd(2026, 11, 2), 23, 59, DateTime.utc(2026, 11, 2, 18, 29)),
      (Ymd(2027, 1, 1), 2, 0, DateTime.utc(2026, 12, 31, 20, 30)),
    ];
    for (final (d, h, m, want) in cases) {
      test('$d $h:$m IST', () => expect(d.istInstant(h, m), want));
    }
  });

  group('AgeSpan.between', () {
    final cases = <(String, String, (int, int, int)?)>[
      ('2000-01-01', '2026-01-01', (26, 0, 0)),
      ('2000-01-01', '2025-12-31', (25, 11, 30)),
      ('2000-08-02', '2026-08-01', (25, 11, 30)),
      ('2000-08-01', '2026-08-01', (26, 0, 0)),
      ('2000-07-31', '2026-08-01', (26, 0, 1)),
      ('1994-08-01', '2026-08-01', (32, 0, 0)),
      ('1994-07-31', '2026-08-01', (32, 0, 1)),
      ('2004-03-15', '2026-10-07', (22, 6, 22)),
      ('2004-10-08', '2026-10-07', (21, 11, 29)),
      ('2004-10-07', '2026-10-07', (22, 0, 0)),
      ('2000-01-31', '2026-03-01', (26, 1, 1)),
      ('2000-01-31', '2026-02-28', (26, 0, 28)),
      ('2000-02-29', '2026-02-28', (25, 11, 30)),
      ('2000-02-29', '2026-03-01', (26, 0, 1)),
      ('2000-02-29', '2024-02-29', (24, 0, 0)),
      ('2026-10-07', '2026-10-07', (0, 0, 0)),
      ('2026-10-07', '2026-10-08', (0, 0, 1)),
      ('2026-09-30', '2026-10-31', (0, 1, 1)),
      ('2026-10-31', '2026-11-30', (0, 0, 30)),
      ('1990-12-31', '2027-01-01', (36, 0, 1)),
      ('1990-12-15', '2027-01-10', (36, 0, 26)),
      ('2001-05-20', '2026-05-19', (24, 11, 29)),
      ('2026-10-08', '2026-10-07', null),
    ];
    for (final (birth, on, want) in cases) {
      test('$birth on $on', () {
        final span = AgeSpan.between(Ymd.tryParse(birth)!, Ymd.tryParse(on)!);
        if (want == null) {
          expect(span, isNull);
        } else {
          expect((span!.years, span.months, span.days), want);
        }
      });
    }
    test('totalMonths', () {
      expect(const AgeSpan(2, 3, 4).totalMonths, 27);
    });
  });

  group('completedYears agrees with AgeSpan.between', () {
    final births = ['1990-01-01', '1994-08-01', '1994-08-02', '2000-02-29', '2004-12-31', '2008-06-15'];
    final ons = ['2026-01-01', '2026-08-01', '2027-01-01', '2026-02-28', '2026-03-01', '2026-12-31'];
    for (final b in births) {
      for (final o in ons) {
        test('$b on $o', () {
          final birth = Ymd.tryParse(b)!, on = Ymd.tryParse(o)!;
          expect(AgeSpan.completedYears(birth, on), AgeSpan.between(birth, on)!.years);
        });
      }
    }
    test('before birth is 0', () {
      expect(AgeSpan.completedYears(Ymd(2026, 10, 8), Ymd(2026, 10, 7)), 0);
    });
  });

  group('Deadline.of', () {
    final today = Ymd(2026, 10, 7);
    final cases = <(String?, Urgency, int?)>[
      (null, Urgency.unknown, null),
      ('2026-10-06', Urgency.closed, -1),
      ('2026-09-01', Urgency.closed, -36),
      ('2026-10-07', Urgency.lastDay, 0),
      ('2026-10-08', Urgency.urgent, 1),
      ('2026-10-09', Urgency.urgent, 2),
      ('2026-10-10', Urgency.urgent, 3),
      ('2026-10-11', Urgency.soon, 4),
      ('2026-10-14', Urgency.soon, 7),
      ('2026-10-15', Urgency.open, 8),
      ('2026-11-05', Urgency.open, 29),
    ];
    for (final (d, u, left) in cases) {
      test('$d', () {
        final dl = Deadline.of(d == null ? null : Ymd.tryParse(d), today);
        expect(dl.urgency, u);
        expect(dl.daysLeft, left);
        expect(dl.isClosed, u == Urgency.closed);
        expect(dl.isUrgent, u == Urgency.lastDay || u == Urgency.urgent);
      });
    }
  });

  group('isPostedToday (India date)', () {
    final today = Ymd(2026, 10, 7);
    final cases = <(DateTime?, bool)>[
      (null, false),
      (DateTime.utc(2026, 10, 7, 5, 12), true),
      (DateTime.utc(2026, 10, 6, 18, 30), true),
      (DateTime.utc(2026, 10, 6, 18, 29), false),
      (DateTime.utc(2026, 10, 7, 18, 29), true),
      (DateTime.utc(2026, 10, 7, 18, 30), false),
      (DateTime.utc(2026, 10, 5, 12), false),
    ];
    for (final (t, want) in cases) {
      test('$t', () => expect(isPostedToday(t, today), want));
    }
  });
}
