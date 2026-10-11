import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/session.dart';
import 'package:roz_quiz/l10n/strings.dart';
import 'package:roz_quiz/ui/mock_screen.dart';

import '../support/harness.dart';

const en = S.en;

List<Question> mockQs() => [
      makeQ(id: 'm0', subject: 'polity', answer: 0, text: 'Mock question 0?'),
      makeQ(id: 'm1', subject: 'polity', answer: 1, text: 'Mock question 1?'),
      makeQ(id: 'm2', subject: 'maths', answer: 2, text: 'Mock question 2?'),
      makeQ(id: 'm3', subject: 'maths', answer: 3, text: 'Mock question 3?'),
    ];

Future<QuizSession> openMock(WidgetTester tester, Harness h,
    {Duration? limit = const Duration(minutes: 2), NegativeMarking neg = NegativeMarking.quarter}) async {
  final session = QuizSession(mode: QuizMode.mock, questions: mockQs(), totalLimit: limit, negative: neg);
  await pumpScreen(
      tester,
      h,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MockTestScreen(session: session, title: 'Mock · SSC'))),
            child: const Text('open'),
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
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('shows the clock, question and controls', (tester) async {
    await openMock(tester, Harness());
    expect(find.text('2:00'), findsOneWidget);
    expect(find.text('Mock question 0?'), findsOneWidget);
    expect(find.text(en.f(T.questionOf, {'n': 1, 'total': 4})), findsOneWidget);
    for (final k in ['mark', 'clear', 'saveNext', 'palette', 'submitTest']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
  });

  testWidgets('the clock runs', (tester) async {
    await openMock(tester, Harness());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1:57'), findsOneWidget);
  });

  testWidgets('answers can be changed and cleared; nothing is revealed', (tester) async {
    final s = await openMock(tester, Harness());
    await tapKey(tester, 'option2');
    await tapKey(tester, 'option1');
    expect(s.states[0].selected, 1);
    expect(find.text(en.t(T.wrong)), findsNothing);
    expect(find.text(en.t(T.correct)), findsNothing);
    await tapKey(tester, 'clear');
    expect(s.states[0].selected, isNull);
  });

  testWidgets('clear is disabled without an answer', (tester) async {
    await openMock(tester, Harness());
    final b = tester.widget<OutlinedButton>(find.byKey(const ValueKey('clear')));
    expect(b.onPressed, isNull);
  });

  testWidgets('save & next and previous', (tester) async {
    final s = await openMock(tester, Harness());
    await tapKey(tester, 'saveNext');
    expect(s.current, 1);
    expect(find.text('Mock question 1?'), findsOneWidget);
    await tester.tap(find.byTooltip(en.t(T.previous)));
    await tester.pump();
    expect(s.current, 0);
  });

  testWidgets('mark for review flags and moves on', (tester) async {
    final s = await openMock(tester, Harness());
    await tapKey(tester, 'mark');
    expect(s.states[0].marked, isTrue);
    expect(s.current, 1);
    expect(s.status(0), PaletteStatus.marked);
  });

  testWidgets('palette shows statuses and jumps to a question', (tester) async {
    final s = await openMock(tester, Harness());
    await tapKey(tester, 'option0');
    await tapKey(tester, 'saveNext');
    await tapKey(tester, 'mark');
    await tapKey(tester, 'palette');
    await tester.pumpAndSettle();
    expect(find.text(en.t(T.palette)), findsWidgets);
    expect(find.text('${en.t(T.legendAnswered)} (1)'), findsOneWidget);
    expect(find.text('${en.t(T.legendMarked)} (1)'), findsOneWidget);
    expect(find.text('${en.t(T.legendNotVisited)} (1)'), findsOneWidget);
    expect(find.text('${en.t(T.legendNotAnswered)} (1)'), findsOneWidget);
    expect(find.bySemanticsLabel('4: ${en.t(T.legendNotVisited)}'), findsOneWidget);
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    expect(s.current, 3);
    expect(find.text('Mock question 3?'), findsOneWidget);
  });

  testWidgets('submit asks for confirmation with counts', (tester) async {
    final h = Harness();
    await openMock(tester, h);
    await tapKey(tester, 'option0');
    await tapKey(tester, 'submitTest');
    await tester.pumpAndSettle();
    expect(find.text(en.t(T.submitConfirmTitle)), findsOneWidget);
    expect(find.text(en.f(T.submitConfirmBody, {'a': 1, 'b': 3, 'c': 0})), findsOneWidget);
    await tester.tap(find.text(en.t(T.cancel)));
    await tester.pumpAndSettle();
    expect(find.text('Mock question 0?'), findsOneWidget);
    expect(h.controller.store.stats.mocks, 0);
  });

  testWidgets('submitting scores with negative marking and shows sections', (tester) async {
    final h = Harness();
    await openMock(tester, h);
    await tapKey(tester, 'option0'); // right
    await tapKey(tester, 'saveNext');
    await tapKey(tester, 'option0'); // wrong
    await tapKey(tester, 'saveNext');
    await tapKey(tester, 'option2'); // right
    await tapKey(tester, 'submitTest');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmSubmit')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text(en.t(T.mockResult)), findsOneWidget);
    expect(find.text('1.75'), findsOneWidget);
    expect(find.text('/ 4'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1/2 · 1'), 200);
    expect(find.text(en.t(T.sectionAnalysis)), findsOneWidget);
    expect(find.text('1/2 · 0.75'), findsOneWidget, reason: 'polity: 1 right, 1 wrong at 1/4');
    expect(find.text('1/2 · 1'), findsOneWidget, reason: 'maths: 1 right, 1 blank');
    expect(h.controller.store.stats.mocks, 1);
    expect(h.controller.store.mistakes.keys, ['m1']);
  });

  testWidgets('last question: save & next becomes submit', (tester) async {
    await openMock(tester, Harness());
    for (var i = 0; i < 3; i++) {
      await tapKey(tester, 'saveNext');
    }
    expect(find.text(en.t(T.submitTest)), findsOneWidget);
    await tapKey(tester, 'saveNext');
    await tester.pumpAndSettle();
    expect(find.text(en.t(T.submitConfirmTitle)), findsOneWidget);
  });

  testWidgets('time up submits on its own', (tester) async {
    final h = Harness();
    await openMock(tester, h, limit: const Duration(seconds: 3));
    await tapKey(tester, 'option0');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text(en.t(T.mockResult)), findsOneWidget);
    expect(h.controller.store.stats.mocks, 1);
  });

  testWidgets('leaving asks first', (tester) async {
    await openMock(tester, Harness());
    await tester.tap(find.byTooltip(en.t(T.close)));
    await tester.pumpAndSettle();
    expect(find.text(en.t(T.exitQuizTitle)), findsOneWidget);
    await tester.tap(find.text(en.t(T.leave)));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('translate shows Hindi', (tester) async {
    await openMock(tester, Harness());
    await tester.tap(find.byTooltip(en.t(T.viewOther)));
    await tester.pump();
    expect(find.text('प्रश्न m0?'), findsOneWidget);
  });

  group('setup', () {
    Future<void> openSetup(WidgetTester tester, Harness h) async {
      await pumpScreen(tester, h, const MockSetupScreen());
      await tester.pumpAndSettle();
    }

    testWidgets('defaults: 25 questions, 1/4 negative, any exam', (tester) async {
      final h = Harness();
      await tester.runAsync(() => h.controller.start());
      await openSetup(tester, h);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '25')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '1/4')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, en.t(T.anyExam))).selected, isTrue);
      expect(find.text('${en.t(T.timeLimit)}: ${en.f(T.minutes, {'n': 15})}'), findsOneWidget);
    });
    testWidgets('target exam is preselected', (tester) async {
      final h = Harness();
      h.controller.settings.targetExams = ['banking'];
      await tester.runAsync(() => h.controller.start());
      await openSetup(tester, h);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, en.exam('banking'))).selected, isTrue);
    });
    testWidgets('starts a test and remembers the negative marking', (tester) async {
      final h = Harness();
      await tester.runAsync(() => h.controller.start());
      await openSetup(tester, h);
      await tester.tap(find.widgetWithText(ChoiceChip, '1/3'));
      await tester.pump();
      expect(find.text(en.f(T.negativeInfo, {'value': '1/3'})), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('startMock')));
      await tester.pumpAndSettle();
      expect(find.text(en.f(T.questionOf, {'n': 1, 'total': 25})), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(h.controller.settings.mockNegative, NegativeMarking.third);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('no questions: start disabled', (tester) async {
      final h = Harness();
      await openSetup(tester, h); // pool not loaded
      expect(find.text(en.t(T.notEnough)), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('startMock'))).onPressed, isNull);
    });
  });
}
