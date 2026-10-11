import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/reminder_plan.dart';
import '../l10n/strings.dart';

/// Schedules the planned notifications. [LocalReminderScheduler] in the
/// app, a recording fake in tests.
abstract class ReminderScheduler {
  /// Whether the app may show notifications (Android 13+ permission).
  Future<bool> enabled();

  /// Asks for the notification permission; true when granted.
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with [plan].
  Future<void> apply(List<PlannedReminder> plan, S strings, int streak);
}

class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({this.granted = true});
  bool granted;
  int permissionRequests = 0;
  List<PlannedReminder> scheduled = [];

  @override
  Future<bool> enabled() async => granted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> apply(List<PlannedReminder> plan, S strings, int streak) async =>
      scheduled = [...plan];
}

/// Local notifications at exact UTC instants (one-offs, re-planned on every
/// app start and after each Daily Quiz). Inexact alarms on purpose: they
/// need no special permission and a few minutes of drift is fine.
class LocalReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _init;

  Future<void> _ensure() => _init ??= () async {
        tzdata.initializeTimeZones();
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
      }();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> enabled() async {
    await _ensure();
    return await _android?.areNotificationsEnabled() ?? true;
  }

  @override
  Future<bool> requestPermission() async {
    await _ensure();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> apply(List<PlannedReminder> plan, S strings, int streak) async {
    try {
      await _ensure();
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= kDailyIdBase && p.id < kStreakIdBase + 100) {
          await _plugin.cancel(id: p.id);
        }
      }
      final daily = AndroidNotificationDetails(
        'daily_quiz',
        strings.t(T.channelDaily),
        importance: Importance.defaultImportance,
      );
      final risk = AndroidNotificationDetails(
        'streak',
        strings.t(T.channelStreak),
        importance: Importance.defaultImportance,
      );
      for (final r in plan) {
        final isDaily = r.kind == ReminderKind.daily;
        await _plugin.zonedSchedule(
          id: r.id,
          title: strings.t(isDaily ? T.notifDailyTitle : T.notifStreakTitle),
          body: isDaily
              ? strings.t(T.notifDailyBody)
              : strings.f(T.notifStreakBody, {'n': streak < 1 ? 1 : streak}),
          scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
          notificationDetails: NotificationDetails(android: isDaily ? daily : risk),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Reminder scheduling failed: $e');
    }
  }
}
