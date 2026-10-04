import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

/// Daily repeating local notifications. Inexact alarms are used on purpose:
/// they need no special permission and a few minutes of drift is fine here.
class Reminders {
  Reminders._();
  static final Reminders instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Water reminders use ids 1..99, habit reminders 1000 + habit id.
  static const _waterBase = 1;
  static const _waterMax = 99;
  static const _habitBase = 1000;

  static const _waterChannel = AndroidNotificationDetails(
    'water',
    'Water reminders',
    channelDescription: 'Reminders to drink water during the day',
    importance: Importance.defaultImportance,
  );
  static const _habitChannel = AndroidNotificationDetails(
    'habits',
    'Habit reminders',
    channelDescription: 'Daily reminders for your habits',
    importance: Importance.defaultImportance,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Timezone lookup failed, using UTC: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Asks for the Android 13+ notification permission. True if granted.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  tz.TZDateTime _next(int minutes) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  Future<void> _daily(int id, int minutes, String title, String body,
      AndroidNotificationDetails channel) {
    return _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _next(minutes),
      notificationDetails: NotificationDetails(android: channel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Cancels and re-creates every reminder from the current settings.
  Future<void> sync(AppStore s) async {
    await init();
    for (var id = _waterBase; id <= _waterMax; id++) {
      await _plugin.cancel(id: id);
    }
    if (s.waterReminders) {
      final times = waterReminderTimes(
          s.wakeMinutes, s.sleepMinutes, s.intervalMinutes);
      for (var i = 0; i < times.length && i < _waterMax; i++) {
        await _daily(_waterBase + i, times[i], 'Time for some water',
            'A glass now keeps you on track for your daily goal.', _waterChannel);
      }
    }
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= _habitBase) await _plugin.cancel(id: p.id);
    }
    for (final h in s.habits) {
      final m = h.reminderMinutes;
      if (m != null) {
        await _daily(_habitBase + h.id, m, h.name,
            "Don't break your streak. Tick it off when it's done.", _habitChannel);
      }
    }
  }
}
