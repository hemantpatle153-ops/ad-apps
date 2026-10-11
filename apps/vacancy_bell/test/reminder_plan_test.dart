import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/logic/alerts.dart';
import 'package:vacancy_bell/logic/reminder_plan.dart';
import 'package:vacancy_bell/models/post.dart';

PostSummary post(String id, String? lastDate) =>
    PostSummary.tryParse({'id': id, 'title': 'T $id', 'lastDate': lastDate})!;

void main() {
  group('reminderInstant: 9 AM India time on the day', () {
    final cases = <(String, int, int, int, DateTime)>[
      ('2026-11-05', 3, 9, 0, DateTime.utc(2026, 11, 2, 3, 30)),
      ('2026-11-05', 1, 9, 0, DateTime.utc(2026, 11, 4, 3, 30)),
      ('2026-11-01', 3, 9, 0, DateTime.utc(2026, 10, 29, 3, 30)),
      ('2027-01-02', 3, 9, 0, DateTime.utc(2026, 12, 30, 3, 30)),
      ('2027-01-01', 1, 9, 0, DateTime.utc(2026, 12, 31, 3, 30)),
      ('2028-03-01', 1, 9, 0, DateTime.utc(2028, 2, 29, 3, 30)),
      ('2026-11-05', 1, 7, 15, DateTime.utc(2026, 11, 4, 1, 45)),
      ('2026-11-05', 1, 0, 0, DateTime.utc(2026, 11, 3, 18, 30)),
      ('2026-11-05', 1, 5, 0, DateTime.utc(2026, 11, 3, 23, 30)),
      ('2026-11-05', 1, 21, 30, DateTime.utc(2026, 11, 4, 16, 0)),
      ('2026-11-05', 3, 23, 59, DateTime.utc(2026, 11, 2, 18, 29)),
    ];
    for (final (last, days, h, m, want) in cases) {
      test('$last -$days d at $h:$m', () {
        expect(reminderInstant(Ymd.tryParse(last)!, days, hour: h, minute: m), want);
      });
    }
    test('default is 09:00', () {
      expect(reminderInstant(Ymd(2026, 11, 5), 1), DateTime.utc(2026, 11, 4, 3, 30));
    });
  });

  group('planReminders', () {
    final now = DateTime.utc(2026, 10, 7, 12, 0); // 17:30 IST

    test('two reminders for a far last date', () {
      final plan = planReminders([post('a', '2026-11-05')], now: now);
      expect(plan.map((r) => r.daysBefore), [3, 1]);
      expect(plan.map((r) => r.when), [DateTime.utc(2026, 11, 2, 3, 30), DateTime.utc(2026, 11, 4, 3, 30)]);
      expect(plan.every((r) => r.postId == 'a'), isTrue);
      expect(plan.first.lastDate, Ymd(2026, 11, 5));
    });

    // Last date relative to today (7 Oct) -> reminders still to come.
    final relative = <(String, List<int>)>[
      ('2026-10-06', []),
      ('2026-10-07', []),
      ('2026-10-08', []), // 1 day before = today 09:00, already past at 17:30
      ('2026-10-09', [1]),
      ('2026-10-10', [1]), // 3 days before = today 09:00, past
      ('2026-10-11', [3, 1]),
      ('2026-12-31', [3, 1]),
    ];
    for (final (last, want) in relative) {
      test('last date $last', () {
        expect(planReminders([post('a', last)], now: now).map((r) => r.daysBefore), want);
      });
    }

    test('a reminder at exactly now is not planned', () {
      final at = DateTime.utc(2026, 10, 8, 3, 30);
      expect(planReminders([post('a', '2026-10-09')], now: at), isEmpty);
    });
    test('one minute before is planned', () {
      final at = DateTime.utc(2026, 10, 8, 3, 29);
      expect(planReminders([post('a', '2026-10-09')], now: at).length, 1);
    });
    test('no last date, no reminder', () => expect(planReminders([post('a', null)], now: now), isEmpty));
    test('duplicates are planned once', () {
      expect(planReminders([post('a', '2026-11-05'), post('a', '2026-11-05')], now: now).length, 2);
    });
    test('sorted by time across posts', () {
      final plan = planReminders([post('late', '2026-12-01'), post('soon', '2026-10-20')], now: now);
      expect(plan.map((r) => r.postId), ['soon', 'soon', 'late', 'late']);
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i - 1].when.isAfter(plan[i].when), isFalse);
      }
    });
    test('custom time', () {
      final plan = planReminders([post('a', '2026-11-05')], now: now, hour: 18, minute: 0);
      expect(plan.first.when, DateTime.utc(2026, 11, 2, 12, 30));
    });
    test('ids are the stable reminder ids', () {
      final plan = planReminders([post('a', '2026-11-05')], now: now);
      expect(plan.map((r) => r.id), [reminderNotificationId('a', 3), reminderNotificationId('a', 1)]);
    });
    test('evening time moves the cut-off', () {
      // 1 day before 8 Oct is today at 20:00 IST, which is still ahead.
      final plan = planReminders([post('a', '2026-10-08')], now: now, hour: 20, minute: 0);
      expect(plan.map((r) => r.daysBefore), [1]);
    });
  });

  group('remindersToCancel', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    final plan = planReminders([post('keep', '2026-11-05')], now: now);
    test('keeps planned ids', () {
      expect(remindersToCancel(plan.map((r) => r.id), plan), isEmpty);
    });
    test('drops reminders for removed posts', () {
      final stale = reminderNotificationId('removed', 1);
      expect(remindersToCancel([stale, ...plan.map((r) => r.id)], plan), {stale});
    });
    test('never touches alert notifications', () {
      expect(remindersToCancel([alertNotificationId('x'), alertSummaryId], plan), isEmpty);
    });
    test('empty plan cancels every reminder', () {
      final ids = plan.map((r) => r.id).toList();
      expect(remindersToCancel(ids, const []), ids.toSet());
    });
  });

  group('canRemind', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    final cases = <(String?, bool)>[
      (null, false),
      ('2026-10-01', false),
      ('2026-10-07', false),
      ('2026-10-08', false),
      ('2026-10-09', true),
      ('2026-11-05', true),
    ];
    for (final (d, want) in cases) {
      test('$d', () => expect(canRemind(d == null ? null : Ymd.tryParse(d), now), want));
    }
  });
}
