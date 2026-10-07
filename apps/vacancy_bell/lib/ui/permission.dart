import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'scope.dart';

/// Explains why notifications help, then asks Android for permission
/// (Android 13+). Returns true when notifications may be shown.
Future<bool> ensureNotificationPermission(BuildContext context) async {
  final app = AppScope.read(context);
  final notifications = app.services.notifications;
  try {
    if (await notifications.permissionGranted()) return true;
  } catch (_) {
    return false;
  }
  if (!context.mounted) return false;
  final s = app.s;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: Text(s.t(L.notifRationaleTitle)),
      content: Text(s.t(L.notifRationale)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false), child: Text(s.t(L.notNow))),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true), child: Text(s.t(L.allow))),
      ],
    ),
  );
  await app.settings.setNotificationPermissionAsked();
  if (ok != true) return false;
  try {
    return await notifications.requestPermission();
  } catch (_) {
    return false;
  }
}
