import 'package:flutter_test/flutter_test.dart';
import 'package:water_habit/store.dart';

import 'support/gen.dart';

void main() {
  group('formatMinutes table', () {
    const table = <int, String>{
      0: '12:00 AM',
      1: '12:01 AM',
      59: '12:59 AM',
      60: '1:00 AM',
      61: '1:01 AM',
      9 * 60 + 5: '9:05 AM',
      10 * 60: '10:00 AM',
      11 * 60 + 59: '11:59 AM',
      12 * 60: '12:00 PM',
      12 * 60 + 1: '12:01 PM',
      12 * 60 + 30: '12:30 PM',
      13 * 60: '1:00 PM',
      15 * 60 + 45: '3:45 PM',
      18 * 60 + 9: '6:09 PM',
      20 * 60: '8:00 PM',
      22 * 60: '10:00 PM',
      23 * 60: '11:00 PM',
      23 * 60 + 59: '11:59 PM',
      8 * 60: '8:00 AM',
      7 * 60 + 30: '7:30 AM',
    };
    table.forEach((m, s) {
      test('$m min -> "$s"', () => expect(formatMinutes(m), s));
    });
  });

  group('formatMinutes round-trips every 5 minutes of the day', () {
    for (var m = 0; m < 24 * 60; m += 5) {
      test('minute $m', () {
        final s = formatMinutes(m);
        expect(parseClock(s), m);
        expect(s.endsWith(m < 720 ? 'AM' : 'PM'), isTrue);
        expect(s.split(':')[1].substring(0, 2), (m % 60).toString().padLeft(2, '0'));
        expect(s.startsWith('0'), isFalse, reason: 'no leading zero hour');
      });
    }
  });

  group('formatMinutes odd minutes keep two-digit padding', () {
    for (var m = 1; m < 24 * 60; m += 37) {
      test('minute $m', () {
        expect(parseClock(formatMinutes(m)), m);
        expect(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$').hasMatch(formatMinutes(m)),
            isTrue);
      });
    }
  });

  group('dayKey edge cases', () {
    final table = <DateTime, String>{
      DateTime(2026, 1, 1): '2026-01-01',
      DateTime(2026, 12, 31): '2026-12-31',
      DateTime(2024, 2, 29): '2024-02-29',
      DateTime(2026, 10, 5, 23, 59, 59): '2026-10-05',
      DateTime(2026, 10, 5, 0, 0, 0): '2026-10-05',
      DateTime(999, 3, 4): '999-03-04',
      DateTime(2000, 9, 9): '2000-09-09',
      DateTime(2026, 3, 8, 12): '2026-03-08',
      DateTime(2026, 11, 1, 1, 30): '2026-11-01',
      DateTime(2026, 1, 32): '2026-02-01',
      DateTime(2026, 13, 1): '2027-01-01',
      DateTime(2026, 3, 0): '2026-02-28',
      DateTime.utc(2030, 7, 4, 6): '2030-07-04',
      DateTime(2100, 2, 29): '2100-03-01',
      DateTime(1999, 12, 31, 23): '1999-12-31',
    };
    table.forEach((d, s) {
      test('$d -> $s', () => expect(dayKey(d), s));
    });
  });

  group('dayKey matches the date for random days', () {
    for (final d in randomDates(7, 120)) {
      test('${d.year}/${d.month}/${d.day}', () {
        final k = dayKey(d);
        expect(k, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        final p = k.split('-').map(int.parse).toList();
        expect(p, [d.year, d.month, d.day]);
        expect(DateTime.parse(k), DateTime(d.year, d.month, d.day));
        expect(dayKey(d.add(const Duration(hours: 13))), k);
      });
    }
  });

  group('dayKey string order follows date order', () {
    final a = randomDates(11, 100);
    final b = randomDates(12, 100);
    for (var i = 0; i < 100; i++) {
      test('pair $i: ${dayKey(a[i])} vs ${dayKey(b[i])}', () {
        expect(dayKey(a[i]).compareTo(dayKey(b[i])).sign,
            a[i].compareTo(b[i]).sign);
      });
    }
  });
}
