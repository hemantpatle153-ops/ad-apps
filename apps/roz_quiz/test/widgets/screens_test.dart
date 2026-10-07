import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/app/controller.dart';
import 'package:roz_quiz/core/bi.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/session.dart';
import 'package:roz_quiz/core/stats.dart';
import 'package:roz_quiz/core/streak.dart';
import 'package:roz_quiz/data/user_store.dart';
import 'package:roz_quiz/l10n/strings.dart';
import 'package:roz_quiz/ui/past_dailies_screen.dart';
import 'package:roz_quiz/ui/progress_tab.dart';
import 'package:roz_quiz/ui/result_screen.dart';
import 'package:roz_quiz/ui/review_screen.dart';
import 'package:roz_quiz/ui/saved_screen.dart';
import 'package:roz_quiz/ui/settings_screen.dart';

import '../support/harness.dart';

const en = S.en;

Finder semanticsWidget(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

QuizResult resultOf(List<Question> qs, List<int?> choices, {QuizMode mode = QuizMode.daily}) =>
    QuizResult.score(
        mode: mode,
        questions: qs,
        choices: choices,
        timesMs: List.filled(qs.length, 2000),
        durationMs: qs.length * 2000);

FinishOutcome outcome({int xp = 50, bool counted = true, int streak = 3, List<Achievement> badges = const []}) =>
    FinishOutcome(
      xpGained: xp,
      levelBefore: 1,
      levelAfter: 1,
      newBadges: badges,
      streak: StreakInfo(current: streak, best: streak, playedToday: true, totalDays: streak),
      countedForStreak: counted,
    );

void main() {
  group('Result screen', () {
    final qs = [for (var i = 0; i < 4; i++) makeQ(id: 'r$i', answer: 0, text: 'Result question $i?')];

    testWidgets('score, headline, tags and stats', (tester) async {
      final r = resultOf(qs, [0, 0, 0, 1]);
      await pumpScreen(tester, Harness(),
          ResultScreen(result: r, outcome: outcome(badges: [Achievement.firstQuiz]), title: 'Daily', isDaily: true));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('3'), findsWidgets);
      expect(find.text('/ 4'), findsOneWidget);
      expect(find.text(en.t(T.greatJob)), findsOneWidget);
      expect(find.text(en.f(T.xpGained, {'n': 50})), findsOneWidget);
      expect(find.text(en.f(T.streakNow, {'n': 3})), findsOneWidget);
      expect(find.textContaining(en.badge(Achievement.firstQuiz).$1), findsOneWidget);
    });
    final headlines = <(List<int?>, T)>[
      ([0, 0, 0, 0], T.perfectScore),
      ([0, 0, 0, 1], T.greatJob),
      ([0, 0, 1, 1], T.goodTry),
      ([0, 1, 1, 1], T.keepGoing),
      ([null, null, null, null], T.keepGoing),
    ];
    for (final (choices, want) in headlines) {
      testWidgets('headline for $choices is ${want.name}', (tester) async {
        await pumpScreen(tester, Harness(),
            ResultScreen(result: resultOf(qs, choices), outcome: outcome(counted: false), title: 'Practice'));
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.text(en.t(want)), findsOneWidget);
      });
    }
    testWidgets('share text for a daily', (tester) async {
      sharedTexts.clear();
      await pumpScreen(tester, Harness(),
          ResultScreen(result: resultOf(qs, [0, 0, 0, 1]), outcome: outcome(), title: 'Daily', isDaily: true));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.ensureVisible(find.byKey(const ValueKey('share')));
      await tester.tap(find.byKey(const ValueKey('share')));
      await tester.pump();
      expect(sharedTexts.single, contains('3/4'));
      expect(sharedTexts.single, contains('3'));
      expect(sharedTexts.single, contains('play.google.com'));
    });
    testWidgets('review shows every answer', (tester) async {
      await pumpScreen(tester, Harness(),
          ResultScreen(result: resultOf(qs, [0, 2, null, 0]), outcome: outcome(), title: 'Daily'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.ensureVisible(find.byKey(const ValueKey('review')));
      await tester.tap(find.byKey(const ValueKey('review')));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.reviewTitle)), findsOneWidget);
      expect(find.text('Result question 0?'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(en.t(T.notAnswered)), 300);
      expect(find.text(en.t(T.notAnswered)), findsOneWidget);
    });
    testWidgets('Back home closes the result', (tester) async {
      await pumpScreen(
          tester,
          Harness(),
          Builder(
              builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ResultScreen(result: resultOf(qs, [0, 0, 0, 0]), outcome: outcome(), title: 'x'))),
                  child: const Text('open'))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await reveal(tester, find.text(en.t(T.backHome)));
      await tester.tap(find.text(en.t(T.backHome)));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('shareTextFor', () {
    final qs = [for (var i = 0; i < 4; i++) makeQ(answer: 0)];
    test('daily, English', () {
      final t = shareTextFor(en, resultOf(qs, [0, 0, 1, null]), isDaily: true, streak: 5);
      expect(t, contains('2/4'));
      expect(t, contains('5'));
    });
    test('daily, Hindi', () {
      final t = shareTextFor(S.hi, resultOf(qs, [0, 0, 1, null]), isDaily: true, streak: 5);
      expect(t, contains('2/4'));
      expect(RegExp(r'[ऀ-ॿ]').hasMatch(t), isTrue);
    });
    test('mock uses the score', () {
      final r = QuizResult.score(
          mode: QuizMode.mock,
          questions: qs,
          choices: [0, 0, 1, null],
          timesMs: [0, 0, 0, 0],
          negative: NegativeMarking.quarter);
      expect(shareTextFor(en, r, isDaily: false, streak: 0), contains('1.75/4'));
    });
  });

  group('Review screen', () {
    testWidgets('marks your answer and the right one', (tester) async {
      final qs = [makeQ(id: 'rv', answer: 1, text: 'Review me?')];
      await pumpScreen(tester, Harness(), ReviewScreen(result: resultOf(qs, [3])));
      await tester.pumpAndSettle();
      expect(find.text('Review me?'), findsOneWidget);
      expect(find.textContaining(en.t(T.yourAnswer).split('{').first.trim()), findsWidgets);
      expect(find.text('Because rv.'), findsOneWidget);
    });
    testWidgets('bookmark from review', (tester) async {
      final h = Harness();
      final qs = [makeQ(id: 'rvb', answer: 1)];
      await pumpScreen(tester, h, ReviewScreen(result: resultOf(qs, [1])));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(en.t(T.bookmark)));
      await tester.pump();
      expect(h.controller.isBookmarked('rvb'), isTrue);
    });
  });

  group('Saved screens', () {
    testWidgets('bookmarks list, remove and practise', (tester) async {
      final h = Harness();
      h.controller.store.bookmarks['b1'] = SavedQuestion(makeQ(id: 'b1', text: 'Saved one?'), kNow);
      h.controller.store.bookmarks['b2'] = SavedQuestion(makeQ(id: 'b2', text: 'Saved two?'), kNow);
      await pumpScreen(tester, h, const SavedScreen(kind: SavedKind.bookmarks));
      await tester.pumpAndSettle();
      expect(find.text('Saved one?'), findsOneWidget);
      expect(find.text(en.f(T.practiceThese, {'n': 2})), findsOneWidget);
      await tester.tap(find.byTooltip(en.t(T.remove)).first);
      await tester.pumpAndSettle();
      expect(h.controller.store.bookmarks.length, 1);
      await tester.tap(find.byKey(const ValueKey('practiceSaved')));
      await tester.pumpAndSettle();
      expect(find.text(en.f(T.questionOf, {'n': 1, 'total': 1})), findsOneWidget);
    });
    testWidgets('swipe to delete a bookmark', (tester) async {
      final h = Harness();
      h.controller.store.bookmarks['b1'] = SavedQuestion(makeQ(id: 'b1', text: 'Swipe me?'), kNow);
      await pumpScreen(tester, h, const SavedScreen(kind: SavedKind.bookmarks));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Swipe me?'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(h.controller.store.bookmarks, isEmpty);
      expect(find.text(en.t(T.bookmarksEmpty)), findsOneWidget);
    });
    testWidgets('mistakes: hint, clear all and revision', (tester) async {
      final h = Harness();
      h.controller.store.mistakes['m1'] = SavedQuestion(makeQ(id: 'm1', answer: 0), kNow);
      await pumpScreen(tester, h, const SavedScreen(kind: SavedKind.mistakes));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.mistakesHint)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('practiceSaved')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('option0')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(h.controller.store.mistakes, isEmpty, reason: 'answered right in revision');
    });
    testWidgets('mistakes clear all', (tester) async {
      final h = Harness();
      h.controller.store.mistakes['m1'] = SavedQuestion(makeQ(id: 'm1'), kNow);
      await pumpScreen(tester, h, const SavedScreen(kind: SavedKind.mistakes));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.t(T.clearAll)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.mistakesEmpty)), findsOneWidget);
    });
  });

  group('Past dailies', () {
    testWidgets('lists published days before today', (tester) async {
      final h = Harness();
      await tester.runAsync(() => h.controller.start());
      await pumpScreen(tester, h, const PastDailiesScreen());
      await tester.pumpAndSettle();
      expect(find.text('6 Oct 2026'), findsOneWidget);
      expect(find.text('5 Oct 2026'), findsOneWidget);
      expect(find.text('7 Oct 2026'), findsNothing);
    });
    testWidgets('played day shows the score', (tester) async {
      final h = Harness();
      h.controller.store.days['2026-10-01'] = const DailyRecord(6, 10, 0, []);
      await pumpScreen(tester, h, const PastDailiesScreen());
      await tester.pumpAndSettle();
      expect(find.text('6/10'), findsOneWidget);
    });
    testWidgets('empty', (tester) async {
      await pumpScreen(tester, Harness(), const PastDailiesScreen());
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.pastDailiesEmpty)), findsOneWidget);
    });
    testWidgets('opening a missing day offline falls back to the bundled quiz', (tester) async {
      final h = Harness();
      await tester.runAsync(() => h.controller.start());
      h.client.offline = true;
      await pumpScreen(tester, h, const PastDailiesScreen());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('6 Oct 2026'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text(en.f(T.questionOf, {'n': 1, 'total': 10})), findsOneWidget);
    });
  });

  group('Progress', () {
    testWidgets('empty stats', (tester) async {
      await pumpScreen(tester, Harness(), const Scaffold(body: ProgressTab()));
      await tester.pumpAndSettle();
      await reveal(tester, find.text(en.t(T.noStatsYet)));
      expect(find.text(en.t(T.noStatsYet)), findsOneWidget);
      await tester.scrollUntilVisible(find.text(en.t(T.weakNone)), 200);
      expect(find.text(en.t(T.weakNone)), findsOneWidget);
    });
    testWidgets('subject accuracy, weak topics and badges', (tester) async {
      final h = Harness();
      h.controller.store.stats.bySubject['polity'] = Tally(10, 3);
      h.controller.store.stats.bySubject['maths'] = Tally(10, 9);
      h.controller.store.badges.add(Achievement.firstQuiz);
      h.controller.store.xp = 150;
      await pumpScreen(tester, h, const Scaffold(body: ProgressTab()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('30% · 3/10'), 200);
      expect(find.text('90% · 9/10'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(en.t(T.practiceThis)), 200);
      expect(find.text(en.t(T.practiceThis)), findsOneWidget);
      await tester.tap(find.text(en.t(T.practiceThis)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('startPractice')), findsOneWidget);
    });
    testWidgets('every badge is listed with earned ones marked', (tester) async {
      final h = Harness();
      h.controller.store.badges.add(Achievement.streak3);
      await pumpScreen(tester, h, const Scaffold(body: ProgressTab()));
      await tester.pumpAndSettle();
      final (name, desc) = en.badge(Achievement.streak3);
      await reveal(tester, find.text(name));
      expect(semanticsWidget('$name. $desc ✓'), findsOneWidget);
      final (n2, d2) = en.badge(Achievement.level10);
      await reveal(tester, find.text(n2));
      expect(semanticsWidget('$n2. $d2'), findsOneWidget);
    });
  });

  group('Settings', () {
    Future<void> open(WidgetTester tester, Harness h) async {
      await pumpScreen(tester, h, const SettingsScreen());
      await tester.pumpAndSettle();
    }

    testWidgets('switch to Hindi', (tester) async {
      final h = Harness();
      await open(tester, h);
      await tester.tap(find.text('हिंदी'));
      await tester.pumpAndSettle();
      expect(h.controller.lang, Lang.hi);
      expect(find.text(S.hi.t(T.settingsTitle)), findsOneWidget);
      expect(UserStore(h.kv).settings.lang, Lang.hi);
    });
    testWidgets('theme', (tester) async {
      final h = Harness();
      await open(tester, h);
      await tester.tap(find.text(en.t(T.themeDark)));
      await tester.pumpAndSettle();
      expect(h.controller.settings.theme, AppTheme.dark);
    });
    testWidgets('timer choice', (tester) async {
      final h = Harness();
      await open(tester, h);
      await tester.tap(find.text('45s'));
      await tester.pumpAndSettle();
      expect(h.controller.settings.timerSeconds, 45);
    });
    testWidgets('turning the daily reminder off clears its notifications', (tester) async {
      final h = Harness();
      await open(tester, h);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('dailyReminder')), 200);
      await tester.tap(find.byKey(const ValueKey('dailyReminder')));
      await tester.pumpAndSettle();
      expect(h.controller.settings.dailyReminder, isFalse);
      expect(h.reminders.scheduled.where((r) => r.id < 200), isEmpty);
    });
    testWidgets('turning it on without permission explains, then asks', (tester) async {
      final h = Harness(permission: false);
      h.controller.settings.dailyReminder = false;
      h.controller.settings.streakReminder = false;
      await open(tester, h);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('dailyReminder')), 200);
      await tester.tap(find.byKey(const ValueKey('dailyReminder')));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.permTitle)), findsOneWidget);
      h.reminders.granted = true;
      await tester.tap(find.byKey(const ValueKey('allowNotifications')));
      await tester.pumpAndSettle();
      expect(h.reminders.permissionRequests, 1);
      expect(h.controller.settings.dailyReminder, isTrue);
    });
    testWidgets('Not now in the explanation does not ask the system', (tester) async {
      final h = Harness(permission: false);
      h.controller.settings.dailyReminder = false;
      await open(tester, h);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('dailyReminder')), 200);
      await tester.tap(find.byKey(const ValueKey('dailyReminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.t(T.notNow)));
      await tester.pumpAndSettle();
      expect(h.reminders.permissionRequests, 0);
    });
    testWidgets('blocked notifications banner', (tester) async {
      final h = Harness(permission: false);
      await open(tester, h);
      await tester.scrollUntilVisible(find.text(en.t(T.notificationsBlocked)), 200);
      expect(find.text(en.t(T.notificationsBlocked)), findsOneWidget);
    });
    testWidgets('target exams', (tester) async {
      final h = Harness();
      await open(tester, h);
      await tester.scrollUntilVisible(find.text(en.t(T.targetExams)), 200);
      await tester.tap(find.text(en.t(T.targetExams)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.exam('railway')));
      await tester.tap(find.text(en.exam('ssc')));
      await tester.pump();
      await tester.tap(find.text(en.t(T.ok)));
      await tester.pumpAndSettle();
      expect(h.controller.settings.targetExams, ['ssc', 'railway']);
    });
    testWidgets('clear cache', (tester) async {
      final h = Harness();
      await tester.runAsync(() => h.controller.start());
      await open(tester, h);
      await reveal(tester, find.text(en.t(T.clearCache)));
      await tester.runAsync(() async {
        await tester.tap(find.text(en.t(T.clearCache)));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(h.cache.files, isEmpty);
      expect(find.text(en.t(T.clearCacheDone)), findsOneWidget);
    });
    testWidgets('about and sources pages', (tester) async {
      await open(tester, Harness());
      await tester.scrollUntilVisible(find.text(en.t(T.sourcesDisclaimer)), 200);
      await tester.tap(find.text(en.t(T.sourcesDisclaimer)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.sourcesBody)), findsOneWidget);
    });
    testWidgets('no ad privacy entry while ads are off', (tester) async {
      await open(tester, Harness());
      await tester.scrollUntilVisible(find.textContaining('1.0.0'), 200);
      expect(find.text(en.t(T.adPrivacy)), findsNothing);
    });
  });

  group('Onboarding', () {
    testWidgets('choose Hindi, exams, allow reminders', (tester) async {
      final h = Harness(onboarded: false);
      await pumpApp(tester, h);
      expect(find.text(en.t(T.obWelcome)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lang-hi')));
      await tester.pumpAndSettle();
      expect(h.controller.lang, Lang.hi);
      await tester.tap(find.byKey(const ValueKey('obContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.hi.exam('upsc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('obContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('obAllow')));
      await tester.pumpAndSettle();
      expect(h.controller.settings.onboarded, isTrue);
      expect(h.controller.settings.targetExams, ['upsc']);
      expect(h.controller.settings.dailyReminder, isTrue);
      expect(h.reminders.scheduled, isNotEmpty);
      expect(find.byKey(const ValueKey('playDaily')), findsOneWidget);
      expect(find.text(S.hi.t(T.playNow)), findsOneWidget);
    });
    testWidgets('Not now turns reminders off', (tester) async {
      final h = Harness(onboarded: false);
      await pumpApp(tester, h);
      await tester.tap(find.byKey(const ValueKey('obContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('obContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('obNotNow')));
      await tester.pumpAndSettle();
      expect(h.controller.settings.onboarded, isTrue);
      expect(h.controller.settings.dailyReminder, isFalse);
      expect(h.reminders.scheduled, isEmpty);
      expect(h.reminders.permissionRequests, 0);
    });
    testWidgets('permission denied keeps reminders off', (tester) async {
      final h = Harness(onboarded: false, permission: false);
      await pumpApp(tester, h);
      await tester.tap(find.byKey(const ValueKey('obContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('obContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('obAllow')));
      await tester.pumpAndSettle();
      expect(h.reminders.permissionRequests, 1);
      expect(h.controller.settings.dailyReminder, isFalse);
    });
    testWidgets('skip goes straight home', (tester) async {
      final h = Harness(onboarded: false);
      await pumpApp(tester, h);
      await tester.tap(find.byKey(const ValueKey('obSkip')));
      await tester.pumpAndSettle();
      expect(h.controller.settings.onboarded, isTrue);
      expect(find.byKey(const ValueKey('playDaily')), findsOneWidget);
    });
    testWidgets('8 AM is the default reminder time shown', (tester) async {
      final h = Harness(onboarded: false);
      await pumpApp(tester, h);
      await tester.tap(find.byKey(const ValueKey('obContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('obContinue')));
      await tester.pumpAndSettle();
      expect(find.textContaining('8:00 AM'), findsOneWidget);
    });
  });

  testWidgets('Day labels in past dailies use IST', (tester) async {
    final h = Harness(now: DateTime.utc(2026, 10, 7, 20)); // 8 Oct 01:30 IST
    expect(h.controller.today, Day(2026, 10, 8));
  });
}
