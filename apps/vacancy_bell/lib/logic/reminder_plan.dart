/// Last-date reminders: when to notify for each post the user set a
/// reminder on.
library;

import '../core/ymd.dart';
import '../models/post.dart';
import 'alerts.dart';

/// Days before the last date that get a reminder.
const reminderDaysBefore = [3, 1];

/// Default reminder time, India time.
const defaultReminderHour = 9;
const defaultReminderMinute = 0;

class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.postId,
    required this.daysBefore,
    required this.when,
    required this.lastDate,
  });

  final int id;
  final String postId;
  final int daysBefore;

  /// UTC instant of the notification.
  final DateTime when;
  final Ymd lastDate;

  @override
  String toString() => 'Reminder($postId, -$daysBefore d, $when)';
}

/// The instant [daysBefore] days before [lastDate] at [hour]:[minute] IST.
DateTime reminderInstant(Ymd lastDate, int daysBefore,
        {int hour = defaultReminderHour, int minute = defaultReminderMinute}) =>
    lastDate.addDays(-daysBefore).istInstant(hour, minute);

/// Reminders still in the future for [posts], sorted by time.
List<PlannedReminder> planReminders(
  Iterable<PostSummary> posts, {
  required DateTime now,
  int hour = defaultReminderHour,
  int minute = defaultReminderMinute,
}) {
  final out = <PlannedReminder>[];
  final seen = <String>{};
  for (final p in posts) {
    final last = p.lastDate;
    if (last == null || !seen.add(p.id)) continue;
    for (final d in reminderDaysBefore) {
      final when = reminderInstant(last, d, hour: hour, minute: minute);
      if (!when.isAfter(now)) continue;
      out.add(PlannedReminder(
        id: reminderNotificationId(p.id, d),
        postId: p.id,
        daysBefore: d,
        when: when,
        lastDate: last,
      ));
    }
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

/// Pending reminder ids that are no longer wanted.
Set<int> remindersToCancel(Iterable<int> pendingIds, List<PlannedReminder> plan) {
  final wanted = {for (final r in plan) r.id};
  return {
    for (final id in pendingIds)
      if (isReminderNotificationId(id) && !wanted.contains(id)) id,
  };
}

/// Whether a reminder can still fire for a post closing on [lastDate].
bool canRemind(Ymd? lastDate, DateTime now,
    {int hour = defaultReminderHour, int minute = defaultReminderMinute}) {
  if (lastDate == null) return false;
  return reminderDaysBefore.any((d) =>
      reminderInstant(lastDate, d, hour: hour, minute: minute).isAfter(now));
}
