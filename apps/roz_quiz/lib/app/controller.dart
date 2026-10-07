import 'package:flutter/foundation.dart';

import '../core/bi.dart';
import '../core/day.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import '../core/report.dart';
import '../core/selection.dart';
import '../core/session.dart';
import '../core/stats.dart';
import '../core/streak.dart';
import '../data/feed_client.dart';
import '../data/repository.dart';
import '../data/user_store.dart';
import '../l10n/strings.dart';
import '../services/reminders.dart';

/// What finishing a quiz changed, for the result screen.
class FinishOutcome {
  const FinishOutcome({
    required this.xpGained,
    required this.levelBefore,
    required this.levelAfter,
    required this.newBadges,
    required this.streak,
    required this.countedForStreak,
  });
  final int xpGained;
  final int levelBefore;
  final int levelAfter;
  final List<Achievement> newBadges;
  final StreakInfo streak;

  /// True when this was today's Daily Quiz, played for the first time.
  final bool countedForStreak;

  bool get leveledUp => levelAfter > levelBefore;
}

/// The app's state and the actions screens call. Screens listen to it.
class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.repo,
    required this.reminders,
    required ReportSink reportSink,
    DateTime Function()? clock,
    SeededRandom Function()? random,
  })  : _clock = clock ?? DateTime.now,
        _random = random ??
            (() => SeededRandom(DateTime.now().microsecondsSinceEpoch)) {
    reports = ReportService(
      reportSink,
      ReportRateLimiter(history: store.reportHistory),
      clock: _clock,
    );
  }

  final UserStore store;
  final QuizRepository repo;
  final ReminderScheduler reminders;
  final DateTime Function() _clock;
  final SeededRandom Function() _random;
  late final ReportService reports;

  DateTime now() => _clock();
  Day get today => Day.ist(_clock());
  Settings get settings => store.settings;
  Lang get lang => settings.lang;
  S get s => S(settings.lang);

  StreakInfo get streak => StreakInfo.compute(store.playedDays, today);
  LevelInfo get level => LevelInfo.fromXp(store.xp);
  DailyRecord? get todayRecord => store.days[today.key];

  Loaded<DailyQuiz>? daily;
  bool loadingDaily = false;
  List<Question> pool = const [];
  DateTime? lastUpdated;
  bool offline = false;
  FeedIndex? feedIndex;

  /// Loads today's quiz, the question pool and the index. Never throws.
  Future<void> start() async {
    await Future.wait([loadToday(), refreshPool(), loadIndex()]);
    await syncReminders();
  }

  Future<void> loadToday({bool refresh = false}) async {
    loadingDaily = true;
    notifyListeners();
    try {
      daily = await repo.daily(today, refresh: refresh);
      offline = daily?.offline ?? false;
    } catch (_) {
      daily = const Loaded.failed(FeedErrorKind.badData);
    }
    loadingDaily = false;
    lastUpdated = await _safe<DateTime?>(repo.lastUpdated);
    notifyListeners();
  }

  Future<void> loadIndex({bool refresh = false}) async {
    try {
      final r = await repo.index(refresh: refresh);
      feedIndex = r.value ?? feedIndex;
    } catch (_) {
      // Keep the old index.
    }
    notifyListeners();
  }

  Future<void> refreshPool() async {
    pool = await _safe(repo.pool) ?? pool;
    notifyListeners();
  }

  Future<T?> _safe<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  /// Downloads the question banks; true on success.
  Future<bool> downloadBanks() async {
    try {
      await repo.downloadBanks();
      offline = false;
      await refreshPool();
      lastUpdated = await _safe<DateTime?>(repo.lastUpdated);
      await loadIndex();
      return true;
    } on FeedException catch (e) {
      offline = e.kind == FeedErrorKind.offline;
      notifyListeners();
      return false;
    }
  }

  Future<Loaded<DailyQuiz>> dailyFor(Day day) => repo.daily(day);

  Future<Loaded<CaDay>> currentAffairs(Day day, {bool refresh = false}) async {
    final r = await repo.currentAffairs(day, refresh: refresh);
    if (r.source == DataSource.network) {
      lastUpdated = await _safe<DateTime?>(repo.lastUpdated);
      pool = await _safe(repo.pool) ?? pool;
      notifyListeners();
    }
    return r;
  }

  /// Picks a practice set and remembers the questions as seen.
  PickResult pickPractice(PracticeFilter filter, int count, {List<Question>? from}) {
    final r = pickWithoutRepeats(
        filter.apply(from ?? pool), count, store.seen, _random());
    _updateSeen(r.seen);
    return r;
  }

  PickResult pickMock(int count, {String? exam}) {
    final r = buildMockTest(pool, count, store.seen, _random(), exam: exam);
    _updateSeen(r.seen);
    return r;
  }

  void _updateSeen(Set<String> seen) {
    store.seen
      ..clear()
      ..addAll(seen);
    store.saveSeen();
  }

  /// Number of pool questions matching [filter].
  int countFor(PracticeFilter filter) => filter.apply(pool).length;

  /// Records a finished quiz: stats, XP, badges, mistakes and, for
  /// today's first Daily Quiz, the streak and reminders.
  Future<FinishOutcome> finishQuiz(QuizResult r, {Day? dailyDate}) async {
    final day = today;
    final countsForStreak = r.mode == QuizMode.daily &&
        dailyDate == day &&
        !store.days.containsKey(day.key);
    final before = LevelInfo.fromXp(store.xp).level;
    if (countsForStreak) {
      store.days[day.key] = DailyRecord(r.correct, r.total, r.durationMs, r.choices);
    }
    final st = streak;
    store.stats.record(r, day);
    final gained = xpFor(r, streak: st.current, countsForStreak: countsForStreak);
    store.xp += gained;
    final now = _clock().toUtc();
    for (final q in r.wrongQuestions) {
      final old = store.mistakes[q.id];
      store.mistakes[q.id] = SavedQuestion(q, now, count: (old?.count ?? 0) + 1);
    }
    if (r.mode == QuizMode.revision) {
      for (final q in r.correctQuestions) {
        store.mistakes.remove(q.id);
      }
    }
    final earned = Achievement.earnedBy(
        Progress(stats: store.stats, bestStreak: st.best, xp: store.xp));
    final fresh = [for (final b in Achievement.values) if (earned.contains(b) && !store.badges.contains(b)) b];
    store.badges.addAll(fresh);
    await Future.wait([
      store.saveDays(),
      store.saveStats(),
      store.saveXp(),
      store.saveMistakes(),
      store.saveBadges(),
    ]);
    if (countsForStreak) await syncReminders();
    notifyListeners();
    return FinishOutcome(
      xpGained: gained,
      levelBefore: before,
      levelAfter: LevelInfo.fromXp(store.xp).level,
      newBadges: fresh,
      streak: st,
      countedForStreak: countsForStreak,
    );
  }

  bool isBookmarked(String id) => store.bookmarks.containsKey(id);

  /// Adds or removes a bookmark; returns true when it is now bookmarked.
  bool toggleBookmark(Question q) {
    final added = !store.bookmarks.containsKey(q.id);
    if (added) {
      store.bookmarks[q.id] = SavedQuestion(q, _clock().toUtc());
    } else {
      store.bookmarks.remove(q.id);
    }
    store.saveBookmarks();
    notifyListeners();
    return added;
  }

  void removeMistake(String id) {
    store.mistakes.remove(id);
    store.saveMistakes();
    notifyListeners();
  }

  void clearMistakes() {
    store.mistakes.clear();
    store.saveMistakes();
    notifyListeners();
  }

  void markCaRead(Day day) {
    if (store.stats.caDaysRead.add(day.key)) {
      final earned = Achievement.earnedBy(Progress(
          stats: store.stats, bestStreak: streak.best, xp: store.xp));
      store.badges.addAll(earned);
      store.saveStats();
      store.saveBadges();
      notifyListeners();
    }
  }

  Future<void> updateSettings(void Function(Settings s) change,
      {bool reschedule = false}) async {
    change(settings);
    notifyListeners();
    await store.saveSettings();
    if (reschedule) await syncReminders();
  }

  /// Re-plans the notifications from the current settings and streak.
  Future<void> syncReminders() async {
    final st = streak;
    final plan = planReminders(
      now: _clock(),
      dailyOn: settings.dailyReminder,
      minutes: settings.reminderMinutes,
      streakOn: settings.streakReminder,
      playedToday: st.playedToday,
      currentStreak: st.current,
    );
    try {
      await reminders.apply(plan, s, st.current);
    } catch (_) {
      // Reminders are a nicety; never break the app over them.
    }
  }

  Future<void> sendReport(
      {required String item, required ReportReason reason, required String note}) async {
    await reports.submit(item: item, reason: reason, note: note);
    await store.saveReports(reports.limiter);
  }

  Future<void> clearCache() async {
    await repo.clearCache();
    lastUpdated = null;
    await refreshPool();
  }
}
