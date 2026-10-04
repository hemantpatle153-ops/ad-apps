import 'package:flutter_test/flutter_test.dart';
import 'package:water_habit/store.dart';

void main() {
  test('water reminders fall inside the waking window', () {
    expect(waterReminderTimes(8 * 60, 22 * 60, 120),
        [600, 720, 840, 960, 1080, 1200, 1320]);
  });

  test('reminder window can cross midnight', () {
    expect(waterReminderTimes(20 * 60, 2 * 60, 180), [23 * 60, 2 * 60]);
  });

  test('habit streak counts back from today or yesterday', () {
    final today = DateTime(2026, 10, 5);
    final h = Habit(id: 1, name: 'Walk', done: {
      dayKey(DateTime(2026, 10, 2)),
      dayKey(DateTime(2026, 10, 3)),
      dayKey(DateTime(2026, 10, 4)),
    });
    expect(h.streak(today), 3);
    h.done.add(dayKey(today));
    expect(h.streak(today), 4);
  });
}
