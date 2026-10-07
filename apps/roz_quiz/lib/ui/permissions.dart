import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'scope.dart';

/// Android 13+ notification permission with an explanation first. Returns
/// true when notifications may be shown.
Future<bool> ensureNotifications(BuildContext context, {bool explain = true}) async {
  final app = AppScope.read(context);
  if (await app.reminders.enabled()) return true;
  if (!context.mounted) return false;
  if (explain) {
    final s = app.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: Text(s.t(T.permTitle)),
        content: Text(s.t(T.permBody)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t(T.notNow))),
          FilledButton(
              key: const ValueKey('allowNotifications'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t(T.allow))),
        ],
      ),
    );
    if (ok != true) return false;
  }
  return app.reminders.requestPermission();
}
