import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:water_habit/store.dart';

import 'support/gen.dart';

Habit habitWithRun(DateTime end, int len, {int id = 1}) => Habit(
      id: id,
      name: 'h',
      done: {for (var i = 0; i < len; i++) dayKey(daysBefore(end, i))},
    );

void main() {
  final today = DateTime(2026, 10, 5);

  group('streak of N days ending today', () {
    for (var n = 0; n <= 30; n++) {
      test('n=$n', () {
        expect(habitWithRun(today, n).streak(today), n);
      });
    }
  });

  group('streak of N days ending yesterday (today still open)', () {
    for (var n = 0; n <= 30; n++) {
      test('n=$n', () {
        final h = habitWithRun(daysBefore(today, 1), n);
        expect(h.doneOn(today), isFalse);
        expect(h.streak(today), n);
      });
    }
  });

  group('streak ending two days ago is broken', () {
    for (var n = 1; n <= 12; n++) {
      test('n=$n', () {
        expect(habitWithRun(daysBefore(today, 2), n).streak(today), 0);
      });
    }
  });

  group('a gap stops the count', () {
    for (var gap = 1; gap <= 15; gap++) {
      test('gap at $gap days back', () {
        final h = habitWithRun(today, 25);
        h.done.remove(dayKey(daysBefore(today, gap)));
        expect(h.streak(today), gap);
      });
    }
  });

  group('time of day passed to streak does not matter', () {
    for (final hour in [0, 1, 6, 11, 12, 17, 23]) {
      test('hour $hour', () {
        final h = habitWithRun(today, 9);
        expect(h.streak(DateTime(2026, 10, 5, hour, 42)), 9);
      });
    }
  });

  group('streak across month/year/DST boundaries', () {
    final ends = [
      DateTime(2026, 3, 1),
      DateTime(2026, 1, 3),
      DateTime(2024, 3, 2),
      DateTime(2026, 3, 10), // US spring forward on Mar 8
      DateTime(2026, 4, 1), // EU spring forward on Mar 29
      DateTime(2026, 11, 3), // US fall back on Nov 1
      DateTime(2026, 10, 27), // EU fall back on Oct 25
      DateTime(2027, 1, 1),
    ];
    for (final e in ends) {
      test('20 days ending ${dayKey(e)}', () {
        expect(habitWithRun(e, 20).streak(e), 20);
      });
    }
  });

  group('doneOn', () {
    final h = Habit(id: 1, name: 'x', done: {'2026-10-05', '2026-01-09'});
    final cases = <(DateTime, bool)>[
      (DateTime(2026, 10, 5), true),
      (DateTime(2026, 10, 5, 23, 59), true),
      (DateTime(2026, 10, 4), false),
      (DateTime(2026, 10, 6), false),
      (DateTime(2026, 1, 9, 7), true),
      (DateTime(2025, 1, 9), false),
      (DateTime(2026, 9, 1), false),
      (DateTime(2026, 1, 9).add(const Duration(hours: 25)), false),
    ];
    for (final (d, exp) in cases) {
      test('${d.toIso8601String()} -> $exp', () => expect(h.doneOn(d), exp));
    }
  });

  group('constructor defaults', () {
    test('done defaults to an empty, mutable set', () {
      final h = Habit(id: 3, name: 'n');
      expect(h.done, isEmpty);
      h.done.add('2026-01-01');
      expect(h.doneOn(DateTime(2026, 1, 1)), isTrue);
      expect(h.reminderMinutes, isNull);
    });
    test('separate habits do not share the default set', () {
      final a = Habit(id: 1, name: 'a'), b = Habit(id: 2, name: 'b');
      a.done.add('2026-01-01');
      expect(b.done, isEmpty);
    });
  });

  group('toJson shape', () {
    test('keys and values', () {
      final h = Habit(id: 7, name: 'Read', reminderMinutes: 1200, done: {'2026-10-05'});
      expect(h.toJson(), {
        'id': 7,
        'name': 'Read',
        'reminder': 1200,
        'done': ['2026-10-05'],
      });
    });
    test('null reminder is kept as null', () {
      expect(Habit(id: 1, name: 'a').toJson()['reminder'], isNull);
      expect(Habit(id: 1, name: 'a').toJson().containsKey('reminder'), isTrue);
    });
  });

  group('fromJson', () {
    test('missing reminder key reads as null', () {
      final h = Habit.fromJson({'id': 1, 'name': 'a', 'done': []});
      expect(h.reminderMinutes, isNull);
    });
    test('duplicate done keys collapse', () {
      final h = Habit.fromJson({
        'id': 1,
        'name': 'a',
        'done': ['2026-01-01', '2026-01-01']
      });
      expect(h.done.length, 1);
    });
    test('non-int id is rejected', () {
      expect(() => Habit.fromJson({'id': '1', 'name': 'a', 'done': []}),
          throwsA(isA<TypeError>()));
    });
  });

  group('JSON round trip of random habits', () {
    final r = Random(99);
    for (var n = 0; n < 80; n++) {
      final id = r.nextInt(100000);
      final name = randomName(r);
      final rem = r.nextBool() ? r.nextInt(1440) : null;
      final done = {
        for (final d in randomDates(n, r.nextInt(40))) dayKey(d),
      };
      test('#$n id $id "$name" reminder $rem days ${done.length}', () {
        final h = Habit(id: id, name: name, reminderMinutes: rem, done: done);
        final back = Habit.fromJson(
            jsonDecode(jsonEncode(h.toJson())) as Map<String, dynamic>);
        expect(back.id, id);
        expect(back.name, name);
        expect(back.reminderMinutes, rem);
        expect(back.done, done);
        expect(back.streak(today), h.streak(today));
      });
    }
  });

  group('random done sets: streak equals oracle', () {
    final r = Random(5);
    for (var n = 0; n < 40; n++) {
      final days = <int>{for (var i = 0; i < 30; i++) if (r.nextDouble() < .75) i};
      test('#$n back-offsets $days', () {
        final h = Habit(
            id: 1, name: 'x', done: {for (final i in days) dayKey(daysBefore(today, i))});
        var start = days.contains(0) ? 0 : 1;
        var exp = 0;
        while (days.contains(start + exp)) {
          exp++;
        }
        expect(h.streak(today), exp);
      });
    }
  });
}
