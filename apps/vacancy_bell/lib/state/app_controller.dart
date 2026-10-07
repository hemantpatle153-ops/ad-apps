import 'package:flutter/foundation.dart';

import '../config.dart';
import '../core/ymd.dart';
import '../data/jobs_repository.dart';
import '../data/settings.dart';
import '../l10n/s.dart';
import '../logic/alerts.dart';
import '../logic/eligibility.dart';
import '../logic/job_query.dart';
import '../logic/reminder_plan.dart';
import '../logic/report.dart';
import '../models/feed_index.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/taxonomy.dart';
import '../services/background.dart';
import '../services/notifications.dart';
import '../services/platform_actions.dart';
import '../services/sync.dart';

/// Everything the UI talks to, so tests can swap any part.
class AppServices {
  AppServices({
    required this.repo,
    required this.settings,
    required this.notifications,
    required this.background,
    required this.reports,
    required this.actions,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final JobsRepository repo;
  final AppSettings settings;
  final NotificationGateway notifications;
  final BackgroundScheduler background;
  final ReportService reports;
  final PlatformActions actions;
  final DateTime Function() clock;
}

/// App state: the post list, the search/filter query, saved posts,
/// reminders and alerts.
class AppController extends ChangeNotifier {
  AppController(this.services) {
    settings.addListener(notifyListeners);
  }

  final AppServices services;
  AppSettings get settings => services.settings;
  JobsRepository get repo => services.repo;
  S get s => S.of(settings.lang);
  DateTime now() => services.clock().toUtc();
  Ymd get today => Ymd.istOf(now());

  FeedIndex? _index;
  FeedResult<FeedIndex>? _last;
  bool _loading = false;
  bool _started = false;
  JobQuery _query = JobQuery.none;

  FeedIndex? get index => _index;
  bool get loading => _loading;

  /// True once the first network attempt finished (success or not).
  bool get started => _started;
  JobQuery get query => _query;

  /// Why the list may be out of date (null when it is fresh).
  FeedProblem? get problem => _last?.problem;

  /// When the shown list was last confirmed with the server.
  DateTime? get checkedAt => _last?.checkedAt;

  bool get feedIsNewer =>
      (_index?.schema ?? AppConfig.supportedSchema) > AppConfig.supportedSchema;

  @override
  void dispose() {
    settings.removeListener(notifyListeners);
    super.dispose();
  }

  /// Shows the offline copy at once, then refreshes from the network.
  Future<void> start() async {
    final cached = await repo.cachedIndex();
    if (cached.data != null && _index == null) {
      _index = cached.data;
      _last = cached;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final r = await repo.index();
      if (r.data != null) {
        _index = r.data;
        _last = r;
        if (r.source != FeedSource.cache) {
          await markIndexSeen(settings, r.data!.posts);
          if (await settings.refreshSaved(r.data!.posts)) {
            await syncReminders(settings, services.notifications, now: now());
          }
        }
      } else {
        // Keep showing what we have, with the new problem.
        _last = FeedResult(
          data: _index,
          source: _index == null ? FeedSource.none : FeedSource.cache,
          checkedAt: _last?.checkedAt,
          problem: r.problem ?? FeedProblem.server,
        );
      }
    } finally {
      _loading = false;
      _started = true;
      notifyListeners();
    }
  }

  void setQuery(JobQuery q) {
    _query = q;
    notifyListeners();
  }

  EligibilityResult eligibilityOf(PostSummary p) {
    final profile = settings.profile;
    if (!profile.canCheckEligibility) return EligibilityResult.notChecked;
    final d = repo.loadedPosts[p.id];
    return d != null ? eligibilityForDetail(profile, d) : eligibilityForSummary(profile, p);
  }

  /// Posts of [type] after search, filters and sort.
  List<PostSummary> postsOf(PostType type) {
    final posts = _index?.posts ?? const <PostSummary>[];
    return applyQuery(
      posts.where((p) => p.type == type),
      _query,
      today: today,
      profile: settings.profile,
      eligibility: eligibilityOf,
    );
  }

  int countOf(PostType type) =>
      _index?.posts.where((p) => p.type == type).length ?? 0;

  /// A summary by id from the list or the saved posts.
  PostSummary? summaryOf(String id) {
    final p = _index?.byId(id);
    if (p != null) return p;
    for (final s in settings.saved) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<FeedResult<PostDetail>> loadPost(String id) async {
    final r = await repo.post(id);
    notifyListeners();
    return r;
  }

  bool isSaved(String id) => settings.isSaved(id);
  bool hasReminder(String id) => settings.hasReminder(id);

  Future<void> setSaved(PostSummary p, bool saved) async {
    await settings.setSaved(p, saved);
    if (!saved && settings.hasReminder(p.id)) {
      await settings.setReminder(p.id, false);
      await syncReminders(settings, services.notifications, now: now());
    }
  }

  /// Can a reminder still fire for [p]?
  bool canRemind(PostSummary p) {
    final (h, m) = settings.reminderTime;
    return canRemindFor(p.lastDate, now(), hour: h, minute: m);
  }

  /// Turns the last-date reminder for [p] on or off. Turning it on also
  /// saves the post. Returns the reminders planned for this post.
  Future<List<PlannedReminder>> setReminder(PostSummary p, bool on) async {
    if (on) {
      if (!settings.isSaved(p.id)) await settings.setSaved(p, true);
      await settings.setReminder(p.id, true);
    } else {
      await settings.setReminder(p.id, false);
    }
    final plan = await syncReminders(settings, services.notifications, now: now());
    return plan.where((r) => r.postId == p.id).toList();
  }

  Future<void> setReminderTime(int hour, int minute) async {
    await settings.setReminderTime(hour, minute);
    await syncReminders(settings, services.notifications, now: now());
  }

  Future<void> setProfile(UserProfile p) => settings.setProfile(p);

  Future<void> setAlertPrefs(AlertPrefs p) async {
    await settings.setAlertPrefs(p);
    try {
      p.enabled ? await services.background.enable() : await services.background.disable();
    } catch (_) {
      // Background work unavailable on this device; the in-app list still works.
    }
  }

  /// Re-registers background work and reminders on launch.
  Future<void> syncBackground() async {
    try {
      settings.alertPrefs.enabled
          ? await services.background.enable()
          : await services.background.disable();
    } catch (_) {}
    await syncReminders(settings, services.notifications, now: now());
  }

  Future<void> clearCache() async {
    await repo.clearCache();
    notifyListeners();
  }

  Future<ReportOutcome> report(ReportDraft draft) => services.reports.submit(draft);
}

/// Whether a reminder can still fire for a post closing on [lastDate].
bool canRemindFor(Ymd? lastDate, DateTime now, {required int hour, required int minute}) =>
    canRemind(lastDate, now, hour: hour, minute: minute);
