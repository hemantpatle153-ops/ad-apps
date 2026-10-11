import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/json_read.dart';
import '../l10n/s.dart';
import '../l10n/strings.dart';
import '../logic/alerts.dart';
import '../logic/reminder_plan.dart';

/// Local notifications. [LocalNotificationGateway] is the real one; tests
/// use a fake that records calls.
abstract class NotificationGateway {
  /// [onTap] receives the payload (a post id) of a tapped notification.
  Future<void> init({void Function(String? payload)? onTap, AppLang lang = AppLang.en});

  /// Asks for the Android 13+ permission. True if notifications may show.
  Future<bool> requestPermission();

  /// Whether notifications are currently allowed (true below Android 13).
  Future<bool> permissionGranted();

  Future<void> schedule(PlannedReminder r, {required String title, required String body});
  Future<void> show(AlertMessage m);
  Future<List<int>> pendingIds();
  Future<void> cancel(int id);

  /// Payload of the notification that launched the app, if any.
  Future<String?> launchPayload();
}

class LocalNotificationGateway implements NotificationGateway {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  late tz.Location _india;
  AppLang _lang = AppLang.en;

  AndroidNotificationDetails _reminderChannel() => AndroidNotificationDetails(
        'reminders',
        S.of(_lang).t(L.channelReminders),
        importance: Importance.high,
        priority: Priority.high,
      );

  AndroidNotificationDetails _alertChannel() => AndroidNotificationDetails(
        'alerts',
        S.of(_lang).t(L.channelAlerts),
        importance: Importance.defaultImportance,
        groupKey: 'in.onlysoftware.vacancy_bell.alerts',
      );

  @override
  Future<void> init({void Function(String? payload)? onTap, AppLang lang = AppLang.en}) async {
    _lang = lang;
    if (_ready) return;
    tzdata.initializeTimeZones();
    _india = tz.getLocation('Asia/Kolkata');
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
      );
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  @override
  Future<bool> permissionGranted() async =>
      await _android?.areNotificationsEnabled() ?? true;

  @override
  Future<void> schedule(PlannedReminder r, {required String title, required String body}) =>
      _plugin.zonedSchedule(
        id: r.id,
        title: title,
        body: body,
        payload: r.postId,
        scheduledDate: tz.TZDateTime.from(r.when, _india),
        notificationDetails: NotificationDetails(android: _reminderChannel()),
        // Inexact needs no special permission; a few minutes of drift is fine.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );

  @override
  Future<void> show(AlertMessage m) => _plugin.show(
        id: m.id,
        title: m.title,
        body: m.body,
        payload: m.postId,
        notificationDetails: NotificationDetails(android: _alertChannel()),
      );

  @override
  Future<List<int>> pendingIds() async =>
      [for (final p in await _plugin.pendingNotificationRequests()) p.id];

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return d.notificationResponse?.payload;
  }
}
