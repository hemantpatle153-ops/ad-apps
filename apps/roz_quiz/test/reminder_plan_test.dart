import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/reminder_plan.dart';

/// [h]:[m] IST on 2026-10-07 as a UTC instant.
DateTime ist(int h, [int m = 0, int dayOffset = 0]) =>
    Day(2026, 10, 7).addDays(dayOffset).atIst(h * 60 + m);

List<PlannedReminder> plan({
  DateTime? now,
  bool dailyOn = true,
  int minutes = kDefaultReminderMinutes,
  bool streakOn = true,
  bool playedToday = false,
  int streak = 0,
  int risk = kStreakRiskMinutes,
  int days = 14,
}) =>
    planReminders(
      now: now ?? ist(6),
      dailyOn: dailyOn,
      minutes: minutes,
      streakOn: streakOn,
      playedToday: playedToday,
      currentStreak: streak,
      riskMinutes: risk,
      days: days,
    );

void main() {
  group('constants', () {
    test('8 AM default and 8 PM risk', () {
      expect(kDefaultReminderMinutes, 480);
      expect(kStreakRiskMinutes, 1200);
    });
    test('id ranges do not overlap', () {
      expect(kDailyIdBase + 14, lessThan(kStreakIdBase));
    });
  });

  group('daily reminder', () {
    test('8 AM IST is 02:30 UTC', () {
      final p = plan();
      expect(p.first.at, DateTime.utc(2026, 10, 7, 2, 30));
      expect(p.first.kind, ReminderKind.daily);
      expect(p.first.id, kDailyIdBase);
      expect(p.first.day, Day(2026, 10, 7));
    });
    test('14 days planned, one per day', () {
      final p = plan(streakOn: false);
      expect(p.length, 14);
      for (var i = 0; i < 14; i++) {
        expect(p[i].id, kDailyIdBase + i);
        expect(p[i].at, ist(8, 0, i));
        expect(p[i].day, Day(2026, 10, 7).addDays(i));
      }
    });
    test('custom number of days', () => expect(plan(streakOn: false, days: 3).length, 3));
    test('today skipped when the time has passed', () {
      final p = plan(now: ist(9), streakOn: false);
      expect(p.length, 13);
      expect(p.first.id, kDailyIdBase + 1);
    });
    test('exactly at the reminder time counts as passed', () {
      final p = plan(now: ist(8), streakOn: false);
      expect(p.first.id, kDailyIdBase + 1);
    });
    test('today skipped when played', () {
      final p = plan(playedToday: true, streakOn: false);
      expect(p.length, 13);
      expect(p.first.day, Day(2026, 10, 8));
    });
    test('off means none', () {
      expect(plan(dailyOn: false, streakOn: false), isEmpty);
    });
    test('custom time 21:45', () {
      final p = plan(minutes: 21 * 60 + 45, streakOn: false);
      expect(p.first.at, ist(21, 45));
    });
    test('minutes are clamped into the day', () {
      expect(plan(minutes: -30, streakOn: false, now: ist(0, 0) .subtract(const Duration(minutes: 1))).first.at, ist(0));
      expect(plan(minutes: 5000, streakOn: false).first.at, ist(23, 59));
    });
    test('works across a month end', () {
      final now = Day(2026, 10, 31).atIst(6 * 60);
      final p = planReminders(
          now: now, dailyOn: true, minutes: 480, streakOn: false, playedToday: false, currentStreak: 0);
      expect(p[1].day, Day(2026, 11, 1));
    });
    test('phone in another timezone: IST time still exact', () {
      // 2026-10-07 23:00 UTC is already 2026-10-08 04:30 IST.
      final p = plan(now: DateTime.utc(2026, 10, 7, 23), streakOn: false);
      expect(p.first.day, Day(2026, 10, 8));
      expect(p.first.at, DateTime.utc(2026, 10, 8, 2, 30));
    });
    test('local DateTime input is handled', () {
      final p = plan(now: ist(6).toLocal(), streakOn: false);
      expect(p.first.at, ist(8));
    });
  });

  group('streak at risk', () {
    test('not played, streak alive: tonight at 8 PM', () {
      final p = plan(streak: 4, dailyOn: false);
      expect(p, [PlannedReminder(kStreakIdBase, ReminderKind.streakRisk, ist(20), Day(2026, 10, 7))]);
    });
    test('not played, no streak: nothing', () {
      expect(plan(streak: 0, dailyOn: false), isEmpty);
    });
    test('played today: tomorrow at 8 PM', () {
      final p = plan(playedToday: true, streak: 5, dailyOn: false);
      expect(p.single.id, kStreakIdBase + 1);
      expect(p.single.at, ist(20, 0, 1));
    });
    test('played today with a 1-day streak still guards tomorrow', () {
      expect(plan(playedToday: true, streak: 1, dailyOn: false).length, 1);
    });
    test('past 8 PM and not played: nothing for tonight', () {
      expect(plan(now: ist(21), streak: 3, dailyOn: false), isEmpty);
    });
    test('off means none', () {
      expect(plan(streakOn: false, dailyOn: false, streak: 9), isEmpty);
    });
    test('no nudge on top of the daily reminder', () {
      final p = plan(minutes: 20 * 60, streak: 3);
      expect(p.where((r) => r.kind == ReminderKind.streakRisk), isEmpty);
    });
    test('a nudge at the same time is fine when daily is off', () {
      final p = plan(minutes: 20 * 60, streak: 3, dailyOn: false);
      expect(p.single.kind, ReminderKind.streakRisk);
    });
    test('custom risk time', () {
      final p = plan(streak: 2, dailyOn: false, risk: 22 * 60 + 30);
      expect(p.single.at, ist(22, 30));
    });
  });

  group('combined', () {
    test('sorted by time', () {
      final p = plan(streak: 3);
      for (var i = 1; i < p.length; i++) {
        expect(p[i].at.isAfter(p[i - 1].at), isTrue);
      }
      expect(p.length, 15);
      expect(p[1].kind, ReminderKind.streakRisk);
    });
    test('ids are unique', () {
      final p = plan(streak: 3, playedToday: true);
      expect(p.map((r) => r.id).toSet().length, p.length);
    });
    test('every planned time is in the future', () {
      for (var h = 0; h < 24; h++) {
        final now = ist(h, 17);
        for (final r in plan(now: now, streak: 2)) {
          expect(r.at.isAfter(now), isTrue);
        }
      }
    });
  });

  group('PlannedReminder', () {
    test('equality and hash', () {
      final a = PlannedReminder(1, ReminderKind.daily, ist(8), Day(2026, 10, 7));
      final b = PlannedReminder(1, ReminderKind.daily, ist(8), Day(2026, 10, 7));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(PlannedReminder(2, ReminderKind.daily, ist(8), Day(2026, 10, 7))));
      expect(a, isNot(PlannedReminder(1, ReminderKind.streakRisk, ist(8), Day(2026, 10, 7))));
    });
    test('toString', () {
      expect(PlannedReminder(1, ReminderKind.daily, ist(8), Day(2026, 10, 7)).toString(),
          contains('#1@2026-10-07T02:30'));
    });
  });

  group('formatMinutes', () {
    final cases = {
      0: ('12:00 AM', '00:00'),
      59: ('12:59 AM', '00:59'),
      480: ('8:00 AM', '08:00'),
      719: ('11:59 AM', '11:59'),
      720: ('12:00 PM', '12:00'),
      780: ('1:00 PM', '13:00'),
      1200: ('8:00 PM', '20:00'),
      1439: ('11:59 PM', '23:59'),
      -5: ('12:00 AM', '00:00'),
      9999: ('11:59 PM', '23:59'),
    };
    cases.forEach((m, want) {
      test('$m minutes', () {
        expect(formatMinutes(m), want.$1);
        expect(formatMinutes(m, h12: false), want.$2);
      });
    });
  });
}
