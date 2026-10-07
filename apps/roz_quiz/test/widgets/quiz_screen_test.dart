import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/bi.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/report.dart';
import 'package:roz_quiz/core/session.dart';
import 'package:roz_quiz/l10n/strings.dart';
import 'package:roz_quiz/ui/quiz_screen.dart';

import '../support/harness.dart';

const en = S.en;

List<Question> questions(int n) => [
      for (var i = 0; i < n; i++)
        makeQ(id: 'wq$i', answer: i % 4, text: 'English question $i?', subject: 'polity')
    ];

Future<QuizSession> openQuiz(WidgetTester tester, Harness h,
    {int n = 3, Duration? limit, QuizMode mode = QuizMode.practice, Day? dailyDate, List<Question>? qs}) async {
  final session = QuizSession(mode: mode, questions: qs ?? questions(n), perQuestionLimit: limit);
  await pumpScreen(
      tester,
      h,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => QuizScreen(session: session, title: 'Polity practice', dailyDate: dailyDate))),
              child: const Text('open'),
            ),
          ),
        ),
      ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return session;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('shows the question, its tags and four options', (tester) async {
    await openQuiz(tester, Harness());
    expect(find.text('English question 0?'), findsOneWidget);
    expect(find.text(en.f(T.questionOf, {'n': 1, 'total': 3})), findsOneWidget);
    for (var o = 0; o < 4; o++) {
      expect(find.byKey(ValueKey('option$o')), findsOneWidget);
    }
    expect(find.text(en.subject('polity')), findsWidgets);
    expect(find.byKey(const ValueKey('skip')), findsOneWidget);
    expect(find.byKey(const ValueKey('next')), findsNothing);
  });

  testWidgets('right answer shows Correct and the explanation', (tester) async {
    final s = await openQuiz(tester, Harness());
    await tapKey(tester, 'option0');
    expect(s.states[0].selected, 0);
    expect(find.text(en.t(T.correct)), findsOneWidget);
    expect(find.text('Because wq0.'), findsOneWidget);
    expect(find.byKey(const ValueKey('next')), findsOneWidget);
  });

  testWidgets('wrong answer shows Not quite and the right option', (tester) async {
    await openQuiz(tester, Harness());
    await tapKey(tester, 'option2');
    expect(find.text(en.t(T.wrong)), findsOneWidget);
    expect(find.textContaining('Option 0 of wq0'), findsWidgets);
  });

  testWidgets('the first answer is final', (tester) async {
    final s = await openQuiz(tester, Harness());
    await tapKey(tester, 'option2');
    await tester.tap(find.byKey(const ValueKey('option0')), warnIfMissed: false);
    await tester.pump();
    expect(s.states[0].selected, 2);
  });

  testWidgets('next goes to the following question', (tester) async {
    await openQuiz(tester, Harness());
    await tapKey(tester, 'option0');
    await tapKey(tester, 'next');
    expect(find.text('English question 1?'), findsOneWidget);
    expect(find.text(en.f(T.questionOf, {'n': 2, 'total': 3})), findsOneWidget);
  });

  testWidgets('skip leaves the question unanswered', (tester) async {
    final s = await openQuiz(tester, Harness());
    await tapKey(tester, 'skip');
    expect(s.current, 1);
    expect(s.states[0].answered, isFalse);
  });

  testWidgets('last question: See result, then the result screen', (tester) async {
    final h = Harness();
    await openQuiz(tester, h, n: 2);
    await tapKey(tester, 'option0');
    await tapKey(tester, 'next');
    await tapKey(tester, 'option0');
    expect(find.text(en.t(T.seeResult)), findsOneWidget);
    await tapKey(tester, 'next');
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text(en.t(T.resultTitle)), findsOneWidget);
    expect(h.controller.store.stats.quizzes, 1);
    expect(h.controller.store.mistakes.keys, ['wq1']);
  });

  testWidgets('skip on the last question says Finish', (tester) async {
    await openQuiz(tester, Harness(), n: 1);
    expect(find.text(en.t(T.finish)), findsOneWidget);
    await tapKey(tester, 'skip');
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text(en.t(T.resultTitle)), findsOneWidget);
  });

  testWidgets('timer counts down and times the question out', (tester) async {
    final s = await openQuiz(tester, Harness(), limit: const Duration(seconds: 5));
    expect(find.text('0:05'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:03'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(s.states[0].timedOut, isTrue);
    expect(find.text(en.t(T.timeUp)), findsOneWidget);
    expect(find.byKey(const ValueKey('next')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no timer chip without a limit', (tester) async {
    await openQuiz(tester, Harness());
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });

  testWidgets('translate button flips this question to Hindi', (tester) async {
    await openQuiz(tester, Harness());
    await tester.tap(find.byTooltip(en.t(T.viewOther)));
    await tester.pumpAndSettle();
    expect(find.text('प्रश्न wq0?'), findsOneWidget);
    await tester.tap(find.byTooltip(en.t(T.viewOther)));
    await tester.pumpAndSettle();
    expect(find.text('English question 0?'), findsOneWidget);
  });

  testWidgets('Hindi users see Hindi first', (tester) async {
    await openQuiz(tester, Harness(lang: Lang.hi));
    expect(find.text('प्रश्न wq0?'), findsOneWidget);
    expect(find.text(S.hi.f(T.questionOf, {'n': 1, 'total': 3})), findsOneWidget);
  });

  testWidgets('bookmark toggles and says so', (tester) async {
    final h = Harness();
    await openQuiz(tester, h);
    await tester.tap(find.byTooltip(en.t(T.bookmark)));
    await tester.pump();
    expect(h.controller.isBookmarked('wq0'), isTrue);
    expect(find.text(en.t(T.bookmarkAdded)), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await tester.tap(find.byTooltip(en.t(T.removeBookmark)));
    await tester.pump();
    expect(h.controller.isBookmarked('wq0'), isFalse);
  });

  testWidgets('close without answers leaves at once', (tester) async {
    await openQuiz(tester, Harness());
    await tester.tap(find.byTooltip(en.t(T.close)));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('close after answering asks first; Stay keeps the quiz', (tester) async {
    await openQuiz(tester, Harness());
    await tapKey(tester, 'option0');
    await tester.tap(find.byTooltip(en.t(T.close)));
    await tester.pumpAndSettle();
    expect(find.text(en.t(T.exitQuizTitle)), findsOneWidget);
    await tester.tap(find.text(en.t(T.stay)));
    await tester.pumpAndSettle();
    expect(find.text('English question 0?'), findsOneWidget);
    await tester.tap(find.byTooltip(en.t(T.close)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.t(T.leave)));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the system back button also asks', (tester) async {
    await openQuiz(tester, Harness());
    await tapKey(tester, 'option0');
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text(en.t(T.exitQuizTitle)), findsOneWidget);
  });

  group('report sheet', () {
    testWidgets('sends a wrong-answer report', (tester) async {
      final h = Harness();
      await openQuiz(tester, h);
      await tester.tap(find.byTooltip(en.t(T.report)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.reportTitle)), findsOneWidget);
      await tester.tap(find.text(en.t(T.send)));
      await tester.pumpAndSettle();
      expect(h.reports.sent.single.item, 'wq0');
      expect(h.reports.sent.single.reason, 'wrong_answer');
      expect(find.text(en.t(T.reportThanks)), findsOneWidget);
    });
    testWidgets('Other needs a note', (tester) async {
      final h = Harness();
      await openQuiz(tester, h);
      await tester.tap(find.byTooltip(en.t(T.report)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.t(T.reasonOther)));
      await tester.pump();
      await tester.tap(find.text(en.t(T.send)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.reportNoteRequired)), findsOneWidget);
      expect(h.reports.sent, isEmpty);
      await tester.enterText(find.byType(TextField), 'The year is wrong');
      await tester.tap(find.text(en.t(T.send)));
      await tester.pumpAndSettle();
      expect(h.reports.sent.single.note, 'The year is wrong');
      expect(h.reports.sent.single.reason, 'other');
    });
    testWidgets('translation report is tagged', (tester) async {
      final h = Harness();
      await openQuiz(tester, h);
      await tester.tap(find.byTooltip(en.t(T.report)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.t(T.reasonTranslation)));
      await tester.enterText(find.byType(TextField), 'Option C Hindi is wrong');
      await tester.tap(find.text(en.t(T.send)));
      await tester.pumpAndSettle();
      expect(h.reports.sent.single.reason, 'translation');
      expect(h.reports.sent.single.note, 'Option C Hindi is wrong');
    });
    testWidgets('offline shows an error and keeps the sheet open', (tester) async {
      final h = Harness()..reports.fail = true;
      await openQuiz(tester, h);
      await tester.tap(find.byTooltip(en.t(T.report)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.t(T.send)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.reportOffline)), findsOneWidget);
      expect(find.text(en.t(T.reportTitle)), findsOneWidget);
    });
    testWidgets('already reported question says so', (tester) async {
      final h = Harness();
      await h.controller.sendReport(item: 'wq0', reason: ReportReason.wrongAnswer, note: '');
      h.now = h.now.add(const Duration(hours: 1));
      await openQuiz(tester, h);
      await tester.tap(find.byTooltip(en.t(T.report)));
      await tester.pumpAndSettle();
      expect(find.text(en.t(T.reportAlready)), findsOneWidget);
      expect(find.text(en.t(T.send)), findsNothing);
    });
  });

  testWidgets("today's daily quiz counts for the streak", (tester) async {
    final h = Harness();
    await openQuiz(tester, h, n: 1, mode: QuizMode.daily, dailyDate: Day(2026, 10, 7));
    await tapKey(tester, 'option0');
    await tapKey(tester, 'next');
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(h.controller.streak.current, 1);
    expect(find.text(en.f(T.streakNow, {'n': 1})), findsOneWidget);
  });
}
