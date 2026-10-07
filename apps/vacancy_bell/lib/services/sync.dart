/// Glue between storage, the feed and notifications. Runs in the app and in
/// the background check, and is tested with fakes.
library;

import '../data/jobs_repository.dart';
import '../data/settings.dart';
import '../l10n/s.dart';
import '../l10n/strings.dart';
import '../logic/alerts.dart';
import '../logic/reminder_plan.dart';
import '../models/post.dart';
import 'notifications.dart';

/// Re-creates the last-date reminders from the saved posts that have a
/// reminder on. Returns the plan that was scheduled.
Future<List<PlannedReminder>> syncReminders(
  AppSettings settings,
  NotificationGateway notifications, {
  required DateTime now,
}) async {
  final ids = settings.reminders;
  final posts = settings.saved.where((p) => ids.contains(p.id));
  final (hour, minute) = settings.reminderTime;
  final plan = planReminders(posts, now: now, hour: hour, minute: minute);
  final s = S.of(settings.lang);
  final byId = {for (final p in posts) p.id: p};
  try {
    for (final id in remindersToCancel(await notifications.pendingIds(), plan)) {
      await notifications.cancel(id);
    }
    for (final r in plan) {
      final p = byId[r.postId]!;
      await notifications.schedule(
        r,
        title: reminderTitle(s, p, r.daysBefore),
        body: s.t(L.notifReminderBody, {'date': s.date(r.lastDate)}),
      );
    }
  } catch (_) {
    // Notifications unavailable (no permission, plugin missing): the app
    // keeps working without reminders.
  }
  return plan;
}

String reminderTitle(S s, PostSummary p, int daysBefore) => s.t(
      daysBefore == 1 ? L.notifReminder1 : L.notifReminder3,
      {'title': s.text(p.title)},
    );

/// Alert wording for [s]'s language.
List<AlertMessage> alertMessagesFor(S s, List<PostSummary> matches) =>
    buildAlertMessages(
      matches,
      s.lang,
      singleTitle: (p) => s.t(L.notifNewJob, {'title': s.text(p.title)}),
      singleBody: (p) {
        final org = s.text(p.org);
        if (p.lastDate == null) return org.isEmpty ? s.t(L.lastDateUnknown) : org;
        final date = s.date(p.lastDate!);
        return org.isEmpty
            ? s.t(L.lastDateOn, {'date': date})
            : s.t(L.notifNewJobBody, {'org': org, 'date': date});
      },
      summaryTitle: (n) => s.t(L.notifManyTitle, {'n': n}),
      summaryBody: (top) => top.map((p) => s.text(p.title)).join(' · '),
    );

/// The periodic new-post check. Returns how many notifications were shown.
Future<int> runAlertCheck({
  required JobsRepository repo,
  required AppSettings settings,
  required NotificationGateway notifications,
  required DateTime now,
}) async {
  await settings.reload();
  final prefs = settings.alertPrefs;
  final result = await repo.index();
  final index = result.data;
  // Nothing new can come from the cached copy.
  if (index == null || result.source == FeedSource.cache) return 0;
  await settings.refreshSaved(index.posts);
  final check = findNewAlerts(index, settings.seenIds, prefs, settings.profile, now: now);
  await settings.setSeenIds(check.seen);
  await settings.setLastAlertCheck(now);
  if (!prefs.enabled || check.matches.isEmpty) return 0;
  if (!await notifications.permissionGranted()) return 0;
  final messages = alertMessagesFor(S.of(settings.lang), check.matches);
  for (final m in messages) {
    await notifications.show(m);
  }
  return messages.length;
}

/// After the app itself loaded the list, everything in it counts as seen:
/// the user doesn't need a notification for a post they could already see.
Future<void> markIndexSeen(AppSettings settings, List<PostSummary> posts) async {
  final seen = settings.seenIds;
  final ids = [for (final p in posts) p.id];
  final merged = <String>{...ids, ...?seen}.take(maxSeenIds).toList();
  await settings.setSeenIds(merged);
}
