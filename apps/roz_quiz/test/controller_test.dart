import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/app/controller.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/reminder_plan.dart';
import 'package:roz_quiz/core/report.dart';
import 'package:roz_quiz/core/selection.dart';
import 'package:roz_quiz/core/session.dart';
import 'package:roz_quiz/core/stats.dart';
import 'package:roz_quiz/data/cache_store.dart';
import 'package:roz_quiz/data/repository.dart';
import 'package:roz_quiz/data/user_store.dart';
import 'package:roz_quiz/l10n/strings.dart';
import 'package:roz_quiz/services/reminders.dart';

import 'support/harness.dart';

final today = Day(2026, 10, 7);

/// Plays [qs] with the pattern of c/w/- answers.
QuizResult play(List<Question> qs, String pattern, {QuizMode mode = QuizMode.daily}) =>
    QuizResult.score(
      mode: mode,
      questions: qs,
      choices: [
        for (var i = 0; i < qs.length; i++)
          switch (pattern[i]) {
            'c' => qs[i].answer,
            'w' => (qs[i].answer + 1) % 4,
            _ => null,
          }
      ],
      timesMs: List.filled(qs.length, 1000),
      durationMs: qs.length * 1000,
    );

void main() {
  group('start', () {
    test('loads today, the pool and the index', () async {
      final h = Harness();
      await h.controller.start();
      final c = h.controller;
      expect(c.daily!.source, DataSource.network);
      expect(c.daily!.value!.questions.length, 10);
      expect(c.loadingDaily, isFalse);
      expect(c.offline, isFalse);
      expect(c.pool.length, greaterThanOrEqualTo(150));
      expect(c.feedIndex, isNotNull);
      expect(c.lastUpdated, kNow);
    });
    test('offline: bundled daily and offline flag', () async {
      final h = Harness(offline: true);
      await h.controller.start();
      expect(h.controller.daily!.source, DataSource.bundled);
      expect(h.controller.offline, isTrue);
      expect(h.controller.feedIndex, isNull);
      expect(h.controller.lastUpdated, isNull);
    });
    test('schedules reminders', () async {
      final h = Harness();
      await h.controller.start();
      expect(h.reminders.scheduled, isNotEmpty);
      expect(h.reminders.scheduled.first.kind, ReminderKind.daily);
      expect(h.reminders.scheduled.first.day, today.addDays(1), reason: '10:00 IST is past 8 AM');
    });
    test('notifies listeners', () async {
      final h = Harness();
      var n = 0;
      h.controller.addListener(() => n++);
      await h.controller.start();
      expect(n, greaterThan(0));
    });
    test('today follows the IST clock', () {
      final h = Harness(now: DateTime.utc(2026, 10, 7, 19)); // 00:30 IST on the 8th
      expect(h.controller.today, Day(2026, 10, 8));
    });
  });

  group('finishQuiz', () {
    late Harness h;
    late List<Question> qs;
    setUp(() async {
      h = Harness();
      await h.controller.start();
      qs = h.controller.daily!.value!.questions;
    });

    test("today's daily counts for the streak", () async {
      final o = await h.controller.finishQuiz(play(qs, 'cccccccww-'), dailyDate: today);
      expect(o.countedForStreak, isTrue);
      expect(o.streak.current, 1);
      expect(o.streak.playedToday, isTrue);
      expect(h.controller.todayRecord!.correct, 7);
      expect(h.controller.todayRecord!.choices.length, 10);
      // 7*10 + 2*2 + 20 + 5*1
      expect(o.xpGained, 99);
      expect(h.controller.store.xp, 99);
    });
    test('playing again does not count twice', () async {
      await h.controller.finishQuiz(play(qs, 'cccccccww-'), dailyDate: today);
      final o = await h.controller.finishQuiz(play(qs, 'cccccccccc'), dailyDate: today);
      expect(o.countedForStreak, isFalse);
      expect(h.controller.todayRecord!.correct, 7, reason: 'first attempt is kept');
      expect(o.xpGained, 100);
    });
    test("an old day's daily does not count", () async {
      final o = await h.controller.finishQuiz(play(qs, 'cccccccccc'), dailyDate: today.addDays(-1));
      expect(o.countedForStreak, isFalse);
      expect(h.controller.store.days, isEmpty);
    });
    test('perfect daily bonus and badge', () async {
      final o = await h.controller.finishQuiz(play(qs, 'cccccccccc'), dailyDate: today);
      expect(o.xpGained, 100 + 20 + 30 + 5);
      expect(o.newBadges, containsAll([Achievement.firstQuiz, Achievement.perfectDaily]));
      expect(h.controller.store.badges, containsAll(o.newBadges));
    });
    test('badges are only new once', () async {
      await h.controller.finishQuiz(play(qs, 'cccccccccc'), dailyDate: today);
      final o = await h.controller.finishQuiz(play(qs, 'c---------', mode: QuizMode.practice));
      expect(o.newBadges, isNot(contains(Achievement.firstQuiz)));
    });
    test('streak continues from yesterday', () async {
      h.controller.store.days[today.addDays(-1).key] = const DailyRecord(5, 10, 0, []);
      h.controller.store.days[today.addDays(-2).key] = const DailyRecord(5, 10, 0, []);
      final o = await h.controller.finishQuiz(play(qs, 'cccccccccc'), dailyDate: today);
      expect(o.streak.current, 3);
      expect(o.newBadges, contains(Achievement.streak3));
      expect(o.xpGained, 100 + 20 + 30 + 15);
    });
    test('wrong answers go to mistakes, counted', () async {
      await h.controller.finishQuiz(play(qs, 'wwcccccccc', mode: QuizMode.practice));
      expect(h.controller.store.mistakes.keys.toSet(), {qs[0].id, qs[1].id});
      await h.controller.finishQuiz(play(qs, 'wccccccccc', mode: QuizMode.practice));
      expect(h.controller.store.mistakes[qs[0].id]!.count, 2);
    });
    test('revision clears mistakes answered right', () async {
      await h.controller.finishQuiz(play(qs, 'wwcccccccc', mode: QuizMode.practice));
      final mistakes = h.controller.store.mistakeList.map((s) => s.question).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final first = mistakes.first;
      final other = mistakes.last;
      await h.controller.finishQuiz(play([first, other], 'cw', mode: QuizMode.revision));
      expect(h.controller.store.mistakes.keys, [other.id]);
    });
    test('blank answers are not mistakes', () async {
      await h.controller.finishQuiz(play(qs, '----------', mode: QuizMode.practice));
      expect(h.controller.store.mistakes, isEmpty);
    });
    test('stats are recorded and saved', () async {
      await h.controller.finishQuiz(play(qs, 'cccccccccc'), dailyDate: today);
      expect(h.controller.store.stats.dailies, 1);
      final reloaded = UserStore(h.kv);
      expect(reloaded.stats.dailies, 1);
      expect(reloaded.xp, h.controller.store.xp);
      expect(reloaded.days.keys, [today.key]);
    });
    test('mock bonus', () async {
      final o = await h.controller.finishQuiz(play(qs, 'cc--------', mode: QuizMode.mock));
      expect(o.xpGained, 45);
      expect(o.newBadges, contains(Achievement.firstMock));
    });
    test('level up is reported', () async {
      h.controller.store.xp = 95;
      final o = await h.controller.finishQuiz(play(qs, 'c---------', mode: QuizMode.practice));
      expect(o.levelBefore, 1);
      expect(o.levelAfter, 2);
      expect(o.leveledUp, isTrue);
    });
    test('playing today moves reminders to tomorrow', () async {
      h.now = DateTime.utc(2026, 10, 7, 1); // 06:30 IST, before 8 AM
      await h.controller.syncReminders();
      expect(h.reminders.scheduled.first.day, today);
      await h.controller.finishQuiz(play(qs, 'cccccccccc'), dailyDate: today);
      final daily = h.reminders.scheduled.where((r) => r.kind == ReminderKind.daily);
      expect(daily.first.day, today.addDays(1));
      final risk = h.reminders.scheduled.where((r) => r.kind == ReminderKind.streakRisk);
      expect(risk.single.day, today.addDays(1));
    });
  });

  group('practice and mocks', () {
    late Harness h;
    setUp(() async {
      h = Harness();
      await h.controller.start();
    });

    test('pickPractice respects the filter and remembers seen', () {
      final r = h.controller.pickPractice(const PracticeFilter(subject: 'polity'), 5);
      expect(r.questions.length, 5);
      expect(r.questions.every((q) => q.subject == 'polity'), isTrue);
      expect(h.controller.store.seen, containsAll(r.questions.map((q) => q.id)));
      expect(UserStore(h.kv).seen, containsAll(r.questions.map((q) => q.id)));
    });
    test('no repeats across practice sessions', () {
      final a = h.controller.pickPractice(const PracticeFilter(subject: 'maths'), 7);
      final b = h.controller.pickPractice(const PracticeFilter(subject: 'maths'), 7);
      expect(a.questions.map((q) => q.id).toSet().intersection(b.questions.map((q) => q.id).toSet()),
          isEmpty);
    });
    test('pickPractice from a given list', () {
      final list = [makeQ(id: 'x1'), makeQ(id: 'x2')];
      final r = h.controller.pickPractice(const PracticeFilter(), 10, from: list);
      expect(r.questions.map((q) => q.id).toSet(), {'x1', 'x2'});
    });
    test('PYQ filter uses the downloaded questions with asked', () {
      expect(h.controller.countFor(const PracticeFilter(pyqOnly: true)), 1, reason: 'daily fixture has one PYQ');
    });
    test('countFor', () {
      final all = h.controller.countFor(const PracticeFilter());
      expect(all, h.controller.pool.length);
      expect(h.controller.countFor(const PracticeFilter(subject: 'nope')), 0);
    });
    test('pickMock by exam', () {
      final r = h.controller.pickMock(25, exam: 'ssc');
      expect(r.questions.length, 25);
      expect(r.questions.every((q) => q.exams.contains('ssc')), isTrue);
    });
    test('downloadBanks adds bank questions to the pool', () async {
      final before = h.controller.pool.length;
      expect(await h.controller.downloadBanks(), isTrue);
      expect(h.controller.pool.length, before + 3);
    });
    test('downloadBanks offline', () async {
      h.client.offline = true;
      expect(await h.controller.downloadBanks(), isFalse);
      expect(h.controller.offline, isTrue);
    });
    test('currentAffairs refreshes the pool', () async {
      final before = h.controller.pool.length;
      final r = await h.controller.currentAffairs(today);
      expect(r.value!.notes.length, 3);
      expect(h.controller.pool.length, before + 2);
    });
    test('clearCache', () async {
      await h.controller.clearCache();
      expect(h.controller.lastUpdated, isNull);
      expect(h.controller.pool.length, lessThan(200));
    });
  });

  group('bookmarks, CA and settings', () {
    late Harness h;
    setUp(() => h = Harness());

    test('toggleBookmark', () {
      final q = makeQ(id: 'bm');
      expect(h.controller.toggleBookmark(q), isTrue);
      expect(h.controller.isBookmarked('bm'), isTrue);
      expect(UserStore(h.kv).bookmarks.keys, ['bm']);
      expect(h.controller.toggleBookmark(q), isFalse);
      expect(h.controller.isBookmarked('bm'), isFalse);
    });
    test('removeMistake and clearMistakes', () {
      h.controller.store.mistakes['a'] = SavedQuestion(makeQ(id: 'a'), kNow);
      h.controller.store.mistakes['b'] = SavedQuestion(makeQ(id: 'b'), kNow);
      h.controller.removeMistake('a');
      expect(h.controller.store.mistakes.keys, ['b']);
      h.controller.clearMistakes();
      expect(UserStore(h.kv).mistakes, isEmpty);
    });
    test('markCaRead counts days once and awards the badge on the 7th', () {
      for (var i = 0; i < 6; i++) {
        h.controller.markCaRead(today.addDays(-i));
      }
      h.controller.markCaRead(today);
      expect(h.controller.store.stats.caDaysRead.length, 6);
      expect(h.controller.store.badges, isNot(contains(Achievement.caReader)));
      h.controller.markCaRead(today.addDays(-6));
      expect(h.controller.store.badges, contains(Achievement.caReader));
    });
    test('updateSettings saves and can reschedule', () async {
      await h.controller.updateSettings((s) => s.dailyReminder = false, reschedule: true);
      expect(UserStore(h.kv).settings.dailyReminder, isFalse);
      expect(h.reminders.scheduled.where((r) => r.kind == ReminderKind.daily), isEmpty);
    });
    test('reminder time change', () async {
      await h.controller.updateSettings((s) => s.reminderMinutes = 21 * 60, reschedule: true);
      expect(h.reminders.scheduled.first.at, today.atIst(21 * 60));
    });
    test('a failing scheduler never breaks the app', () async {
      final c = AppController(
        store: UserStore(MemoryKeyValueStore()),
        repo: QuizRepository(
            client: FakeFeedClient(fixtureFeed()), cache: MemoryCacheStore(), bundle: FileBundleLoader()),
        reminders: _BrokenScheduler(),
        reportSink: FakeReportSink(),
        clock: () => kNow,
      );
      await c.start();
      await c.updateSettings((s) => s.streakReminder = false, reschedule: true);
      expect(c.settings.streakReminder, isFalse);
      expect(c.daily!.hasValue, isTrue);
    });
  });

  group('reports', () {
    late Harness h;
    setUp(() => h = Harness());

    test('sendReport stores history', () async {
      await h.controller.sendReport(item: 'q1', reason: ReportReason.wrongAnswer, note: '');
      expect(h.reports.sent.single.item, 'q1');
      expect(UserStore(h.kv).reportHistory.single.$1, 'q1');
    });
    test('the history survives a restart', () async {
      await h.controller.sendReport(item: 'q1', reason: ReportReason.wrongAnswer, note: '');
      final h2 = Harness(kv: h.kv);
      expect(h2.controller.reports.precheck('q1'), ReportProblem.alreadyReported);
    });
    test('offline failure surfaces', () async {
      h.reports.fail = true;
      await expectLater(
          h.controller.sendReport(item: 'q1', reason: ReportReason.wrongAnswer, note: ''),
          throwsA(isA<ReportException>()));
    });
  });
}

class _BrokenScheduler implements ReminderScheduler {
  @override
  Future<bool> enabled() async => throw StateError('no plugin');
  @override
  Future<bool> requestPermission() async => throw StateError('no plugin');
  @override
  Future<void> apply(List<PlannedReminder> plan, S strings, int streak) async =>
      throw StateError('no plugin');
}
