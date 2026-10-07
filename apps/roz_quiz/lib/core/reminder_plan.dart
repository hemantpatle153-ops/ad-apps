import 'day.dart';

enum ReminderKind { daily, streakRisk }

/// One notification to schedule at an exact UTC instant.
class PlannedReminder {
  const PlannedReminder(this.id, this.kind, this.at, this.day);
  final int id;
  final ReminderKind kind;
  final DateTime at;

  /// The IST day it belongs to.
  final Day day;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.kind == kind &&
      other.at == at;

  @override
  int get hashCode => Object.hash(id, kind, at);

  @override
  String toString() => '$kind#$id@${at.toIso8601String()}';
}

/// Notification ids used by [planReminders]: daily 100-199, streak 200-299.
const kDailyIdBase = 100;
const kStreakIdBase = 200;

/// Default reminder: 08:00 IST. Streak-at-risk: 20:00 IST.
const kDefaultReminderMinutes = 8 * 60;
const kStreakRiskMinutes = 20 * 60;

/// Plans the next [days] days of notifications.
///
/// Notifications can't look at the app's state when they fire, so the plan
/// is made of one-off notifications and re-made whenever the app opens or
/// a Daily Quiz is finished:
/// * the daily reminder at [minutes] IST each day, skipped today when
///   today's quiz is already played;
/// * a streak-at-risk reminder at [riskMinutes] IST today when the streak
///   is alive but today is not played yet, and tomorrow when today is
///   played (if tomorrow is played the app re-plans and drops it). Later
///   days get none: by then the streak would already be lost.
///
/// Times that are already past are left out. IST has no daylight saving,
/// so the instants are exact whatever the phone's timezone.
List<PlannedReminder> planReminders({
  required DateTime now,
  required bool dailyOn,
  required int minutes,
  required bool streakOn,
  required bool playedToday,
  required int currentStreak,
  int riskMinutes = kStreakRiskMinutes,
  int days = 14,
}) {
  final today = Day.ist(now);
  final out = <PlannedReminder>[];
  final m = minutes.clamp(0, 24 * 60 - 1);
  for (var i = 0; i < days; i++) {
    final day = today.addDays(i);
    if (dailyOn && !(i == 0 && playedToday)) {
      final at = day.atIst(m);
      if (at.isAfter(now)) {
        out.add(PlannedReminder(kDailyIdBase + i, ReminderKind.daily, at, day));
      }
    }
  }
  if (streakOn) {
    final risky = <int>[
      if (!playedToday && currentStreak > 0) 0,
      if (playedToday) 1,
    ];
    for (final i in risky) {
      final day = today.addDays(i);
      final at = day.atIst(riskMinutes.clamp(0, 24 * 60 - 1));
      // No streak nudge right on top of the daily reminder.
      final clash = dailyOn && at == day.atIst(m);
      if (at.isAfter(now) && !clash) {
        out.add(PlannedReminder(
            kStreakIdBase + i, ReminderKind.streakRisk, at, day));
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// "08:00" style label for minutes after midnight.
String formatMinutes(int minutes, {bool h12 = true}) {
  final m = minutes.clamp(0, 24 * 60 - 1);
  final h = m ~/ 60, mm = (m % 60).toString().padLeft(2, '0');
  if (!h12) return '${h.toString().padLeft(2, '0')}:$mm';
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh:$mm ${h < 12 ? 'AM' : 'PM'}';
}
