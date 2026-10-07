import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/app/app.dart';
import 'package:roz_quiz/core/bi.dart';
import 'package:roz_quiz/data/user_store.dart';
import 'package:roz_quiz/l10n/strings.dart';

import '../support/harness.dart';

/// Walks the main screens. Any overflow or exception fails the test.
Future<void> walk(WidgetTester tester, Harness h) async {
  final s = S(h.controller.lang);
  Future<void> tab(T t) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(s.t(t))));
    await tester.pumpAndSettle();
  }

  await tab(T.tabCurrent);
  await tab(T.tabPractice);
  await reveal(tester, find.byKey(const ValueKey('subject-polity')),
      scrollable: find.byType(Scrollable).last);
  await tester.tap(find.byKey(const ValueKey('subject-polity')));
  await tester.pumpAndSettle();
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
  await tab(T.tabProgress);
  await tab(T.tabToday);
  await tester.tap(find.byKey(const ValueKey('settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('playDaily')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('option1')));
  await tester.pump(const Duration(milliseconds: 600));
  await reveal(tester, find.byKey(const ValueKey('next')));
  await tester.pumpWidget(const SizedBox());
}

void main() {
  for (final lang in Lang.values) {
    for (final scale in [1.0, 1.3]) {
      for (final size in [const Size(360, 690), const Size(411, 891)]) {
        testWidgets('${lang.name}, text x$scale, ${size.width.toInt()}dp: no overflow', (tester) async {
          final h = Harness(lang: lang);
          await pumpApp(tester, h, textScale: scale, size: size);
          await walk(tester, h);
        });
      }
    }
  }

  testWidgets('text scale is capped at 1.3', (tester) async {
    final h = Harness();
    await pumpApp(tester, h, textScale: 2.0);
    final ctx = tester.element(find.byKey(const ValueKey('playDaily')));
    expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(13, 0.01));
    expect(kMaxTextScale, 1.3);
  });

  testWidgets('dark theme renders', (tester) async {
    final h = Harness();
    h.controller.settings.theme = AppTheme.dark;
    await pumpApp(tester, h);
    final ctx = tester.element(find.byKey(const ValueKey('playDaily')));
    expect(Theme.of(ctx).brightness, Brightness.dark);
  });

  testWidgets('Hindi locale is set for Material widgets', (tester) async {
    final h = Harness(lang: Lang.hi);
    await pumpApp(tester, h);
    final ctx = tester.element(find.byKey(const ValueKey('playDaily')));
    expect(Localizations.localeOf(ctx).languageCode, 'hi');
  });

  testWidgets('answer options have letter labels for screen readers', (tester) async {
    final h = Harness();
    await pumpApp(tester, h);
    await tester.tap(find.byKey(const ValueKey('playDaily')));
    await tester.pumpAndSettle();
    final labels = tester
        .widgetList<Semantics>(find.descendant(
            of: find.byKey(const ValueKey('option0')), matching: find.byType(Semantics)))
        .map((s) => s.properties.label ?? '')
        .where((l) => l.isNotEmpty);
    expect(labels.any((l) => l.contains('A')), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tap targets meet the Android guideline on Today', (tester) async {
    final h = Harness();
    await pumpApp(tester, h);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('tap targets meet the Android guideline on a question', (tester) async {
    final h = Harness();
    await pumpApp(tester, h);
    await tester.tap(find.byKey(const ValueKey('playDaily')));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('labelled tap targets on a question', (tester) async {
    final h = Harness();
    await pumpApp(tester, h);
    await tester.tap(find.byKey(const ValueKey('playDaily')));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.pumpWidget(const SizedBox());
  });
}
