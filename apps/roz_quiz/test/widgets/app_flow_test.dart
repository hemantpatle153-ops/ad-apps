import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/bi.dart';
import 'package:roz_quiz/core/selection.dart';
import 'package:roz_quiz/data/user_store.dart';
import 'package:roz_quiz/l10n/strings.dart';

import '../support/harness.dart';

const en = S.en;

Future<void> openTab(WidgetTester tester, T label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(en.t(label))));
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into the middle of the Today list (clear of the
/// navigation bar).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  group('Today', () {
    testWidgets('online: daily card with play button and greeting', (tester) async {
      await pumpApp(tester, Harness());
      expect(find.text(en.t(T.greetMorning)), findsOneWidget);
      expect(find.text('Daily Quiz · 7 Oct'), findsOneWidget);
      expect(find.text(en.f(T.dailyQuizSub, {'n': 10})), findsOneWidget);
      expect(find.byKey(const ValueKey('playDaily')), findsOneWidget);
      expect(find.text(en.t(T.offlineBanner)), findsNothing);
      expect(find.text('7 Oct 2026'), findsOneWidget);
    });
    testWidgets('evening greeting', (tester) async {
      await pumpApp(tester, Harness(now: DateTime.utc(2026, 10, 7, 13)));
      expect(find.text(en.t(T.greetEvening)), findsOneWidget);
    });
    testWidgets('offline: banner and bundled daily still playable', (tester) async {
      await pumpApp(tester, Harness(offline: true));
      expect(find.text(en.t(T.offlineBanner)), findsOneWidget);
      expect(find.text(en.f(T.dailyOfflineSub, {'n': 10})), findsOneWidget);
      expect(find.byKey(const ValueKey('playDaily')), findsOneWidget);
      await reveal(tester, find.text(en.t(T.neverUpdated)));
      expect(find.text(en.t(T.neverUpdated)), findsOneWidget);
    });
    testWidgets('played today: score and review button', (tester) async {
      final h = Harness();
      h.controller.store.days['2026-10-07'] = const DailyRecord(8, 10, 60000, [0, 1, 2, 3, 0, 1, 2, 3, 0, 1]);
      await pumpApp(tester, h);
      expect(find.text(en.f(T.playedScore, {'score': 8, 'total': 10})), findsOneWidget);
      expect(find.byKey(const ValueKey('dailyReview')), findsOneWidget);
      expect(find.byKey(const ValueKey('playDaily')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dailyReview')));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.reviewAnswers)), findsWidgets);
    });
    testWidgets('streak card shows the streak', (tester) async {
      final h = Harness();
      h.controller.store.days['2026-10-06'] = const DailyRecord(5, 10, 0, []);
      h.controller.store.days['2026-10-05'] = const DailyRecord(5, 10, 0, []);
      await pumpApp(tester, h);
      expect(find.text(en.t(T.streakAtRisk)), findsOneWidget);
    });
    testWidgets('playing the daily updates Today', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await tester.tap(find.byKey(const ValueKey('playDaily')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const ValueKey('skip')));
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text(en.t(T.resultTitle)), findsOneWidget);
      await tester.tap(find.byTooltip(en.t(T.close)).last);
      await tester.pumpAndSettle();
      expect(find.text(en.f(T.playedScore, {'score': 0, 'total': 10})), findsOneWidget);
      expect(h.controller.streak.playedToday, isTrue);
    });
    testWidgets('last updated line after a download', (tester) async {
      await pumpApp(tester, Harness());
      await reveal(tester, find.text(en.f(T.updatedAt, {'when': en.t(T.justNow)})));
      expect(find.text(en.f(T.updatedAt, {'when': en.t(T.justNow)})), findsOneWidget);
    });
    testWidgets('quick tiles open their screens', (tester) async {
      await pumpApp(tester, Harness());
      await reveal(tester, find.text(en.t(T.pastDailies)));
      await tester.tap(find.text(en.t(T.bookmarks)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.bookmarksEmpty)), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.t(T.myMistakes)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.mistakesEmpty)), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.t(T.pastDailies)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.pastDailies)), findsWidgets);
    });
  });

  group('tabs', () {
    testWidgets('all four tabs open', (tester) async {
      await pumpApp(tester, Harness());
      await openTab(tester, T.tabCurrent);
      expect(find.text('Swachhata Hi Seva campaign concludes'), findsOneWidget);
      await openTab(tester, T.tabPractice);
      expect(find.byKey(const ValueKey('subject-polity')), findsOneWidget);
      await openTab(tester, T.tabProgress);
      expect(find.text(en.t(T.progressTitle)), findsWidgets);
      await openTab(tester, T.tabToday);
      expect(find.byKey(const ValueKey('playDaily')), findsOneWidget);
    });
    testWidgets('current affairs are not fetched until the tab opens', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      expect(h.client.requests.where((p) => p.contains('current_affairs')), isEmpty);
      await openTab(tester, T.tabCurrent);
      expect(h.client.requests.where((p) => p.contains('current_affairs')), isNotEmpty);
    });
    testWidgets('settings opens from the app bar', (tester) async {
      await pumpApp(tester, Harness());
      await tester.tap(find.byKey(const ValueKey('settings')));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.settings)), findsWidgets);
    });
  });

  group('Current affairs', () {
    testWidgets('swipe through the notes to the quiz card', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await openTab(tester, T.tabCurrent);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text(en.f(T.sourceLabel, {'name': 'PIB'})), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.fling(find.byType(PageView), const Offset(0, -500), 2000);
        await tester.pumpAndSettle();
      }
      expect(find.text(en.t(T.caAllRead)), findsOneWidget);
      expect(h.controller.store.stats.caDaysRead, contains('2026-10-07'));
      await tester.tap(find.byKey(const ValueKey('caQuiz')));
      await tester.pumpAndSettle();
      expect(find.text(en.f(T.questionOf, {'n': 1, 'total': 2})), findsOneWidget);
    });
    testWidgets('a note without a source shows no source line', (tester) async {
      await pumpApp(tester, Harness());
      await openTab(tester, T.tabCurrent);
      for (var i = 0; i < 2; i++) {
        await tester.fling(find.byType(PageView), const Offset(0, -500), 2000);
        await tester.pumpAndSettle();
      }
      expect(find.text('Note without source'), findsOneWidget);
      expect(find.textContaining('Source'), findsNothing);
    });
    testWidgets('empty day', (tester) async {
      await pumpApp(tester, Harness());
      await openTab(tester, T.tabCurrent);
      await tester.tap(find.text('6 Oct'));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.caEmpty)), findsOneWidget);
      expect(find.text(en.t(T.retry)), findsOneWidget);
    });
    testWidgets('offline without a saved copy', (tester) async {
      await pumpApp(tester, Harness(offline: true));
      await openTab(tester, T.tabCurrent);
      expect(find.text(en.t(T.errorOffline)), findsOneWidget);
    });
    testWidgets('offline with a saved copy shows it', (tester) async {
      final h = Harness();
      await tester.runAsync(() => h.controller.currentAffairs(h.controller.today));
      h.client.offline = true;
      h.now = h.now.add(const Duration(hours: 3));
      await pumpApp(tester, h);
      await openTab(tester, T.tabCurrent);
      expect(find.text('Swachhata Hi Seva campaign concludes'), findsOneWidget);
      expect(find.text(en.t(T.offlineBanner)), findsWidgets);
    });
    testWidgets('Hindi notes for Hindi users', (tester) async {
      await pumpApp(tester, Harness(lang: Lang.hi));
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(S.hi.t(T.tabCurrent))));
      await tester.pumpAndSettle();
      expect(find.text('स्वच्छता ही सेवा अभियान संपन्न'), findsOneWidget);
    });
  });

  group('Practice', () {
    testWidgets('subject tiles show counts and open the sheet', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await openTab(tester, T.tabPractice);
      expect(find.text(en.f(T.questionsOffline, {'n': h.controller.pool.length})), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('subject-polity')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('startPractice')), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '20'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('startPractice')));
      await tester.pumpAndSettle();
      final polity = h.controller.countFor(const PracticeFilter(subject: 'polity'));
      expect(find.text(en.f(T.questionOf, {'n': 1, 'total': polity < 20 ? polity : 20})), findsOneWidget);
    });
    testWidgets('by exam', (tester) async {
      await pumpApp(tester, Harness());
      await openTab(tester, T.tabPractice);
      await tester.tap(find.text(en.t(T.byExam)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exam-ssc')), findsOneWidget);
      expect(find.byKey(const ValueKey('subject-polity')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('exam-upsc')));
      await tester.pumpAndSettle();
      expect(find.text(en.exam('upsc')), findsWidgets);
    });
    testWidgets('target exams are listed first', (tester) async {
      final h = Harness();
      h.controller.settings.targetExams = ['teaching'];
      await pumpApp(tester, h);
      await openTab(tester, T.tabPractice);
      await tester.tap(find.text(en.t(T.byExam)));
      await tester.pumpAndSettle();
      final teaching = tester.getTopLeft(find.byKey(const ValueKey('exam-teaching')));
      final ssc = tester.getTopLeft(find.byKey(const ValueKey('exam-ssc')));
      expect(teaching.dy <= ssc.dy && (teaching.dy < ssc.dy || teaching.dx < ssc.dx), isTrue);
    });
    testWidgets('PYQ only with no PYQs says so and disables start', (tester) async {
      await pumpApp(tester, Harness(offline: true));
      await openTab(tester, T.tabPractice);
      await tester.tap(find.text(en.t(T.pyqTitle)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.pyqEmpty)), findsOneWidget);
      final b = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('startPractice')));
      expect(b.onPressed, isNull);
    });
    testWidgets('PYQ from the feed are offered', (tester) async {
      await pumpApp(tester, Harness());
      await openTab(tester, T.tabPractice);
      expect(find.text(en.f(T.available, {'n': 1})), findsOneWidget);
    });
    testWidgets('download more questions', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await openTab(tester, T.tabPractice);
      final before = h.controller.pool.length;
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('download')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(h.controller.pool.length, before + 3);
      expect(find.text(en.t(T.downloadDone)), findsOneWidget);
    });
    testWidgets('download offline fails politely', (tester) async {
      final h = Harness(offline: true);
      await pumpApp(tester, h);
      await openTab(tester, T.tabPractice);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('download')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.downloadFailed)), findsOneWidget);
    });
  });
}
