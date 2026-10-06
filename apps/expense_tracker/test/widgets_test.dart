import 'package:expense_tracker/data.dart';
import 'package:expense_tracker/editor.dart';
import 'package:expense_tracker/insights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Settings> settings([String currency = '₹']) async {
  SharedPreferences.setMockInitialValues({'currency': currency});
  return Settings(await SharedPreferences.getInstance());
}

Future<void> pumpInsights(
    WidgetTester t, List<Expense> items, Settings s, DateTime month) async {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: InsightsView(items: items, settings: s, month: month)),
  ));
}

/// Opens the editor from a button and records what it returns.
Future<List<EditorResult?>> openEditor(
    WidgetTester t, Settings s, Expense? existing) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final results = <EditorResult?>[];
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async =>
              results.add(await showExpenseEditor(context, s, existing)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return results;
}

void main() {
  group('InsightsView', () {
    testWidgets('empty month shows placeholder', (t) async {
      await pumpInsights(t, [], await settings(), DateTime(2025, 2));
      expect(find.text('Nothing to show for this month yet.'), findsOneWidget);
    });

    testWidgets('totals, percentages and daily average for a past month',
        (t) async {
      final m = DateTime(2025, 2); // 28 days
      final items = [
        Expense(amount: 30000, category: 'rent', date: DateTime(2025, 2, 1)),
        Expense(amount: 7000, category: 'food', date: DateTime(2025, 2, 3)),
        Expense(amount: 3000, category: 'food', date: DateTime(2025, 2, 10)),
        Expense(amount: 2000, category: 'fuel', date: DateTime(2025, 2, 28)),
      ];
      await pumpInsights(t, items, await settings(), m);
      expect(find.text('₹420'), findsOneWidget); // total in donut
      expect(find.text('₹300  71%'), findsOneWidget);
      expect(find.text('₹100  24%'), findsOneWidget);
      expect(find.text('₹20  5%'), findsOneWidget);
      expect(find.text('Average ₹15 a day'), findsOneWidget); // 42000 ~/ 28
      // Sorted by spend, largest first.
      final rent = t.getTopLeft(find.text('Rent')).dy;
      final food = t.getTopLeft(find.text('Food')).dy;
      final fuel = t.getTopLeft(find.text('Fuel')).dy;
      expect(rent < food && food < fuel, isTrue);
    });

    testWidgets('unknown categories are grouped under Other', (t) async {
      final items = [
        Expense(amount: 500, category: 'legacy', date: DateTime(2024, 7, 4)),
      ];
      await pumpInsights(t, items, await settings('\$'), DateTime(2024, 7));
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('\$5  100%'), findsOneWidget);
      expect(find.text('Average \$0.16 a day'), findsOneWidget); // 500 ~/ 31
    });

    testWidgets('one row per category present', (t) async {
      final items = [
        for (var i = 0; i < Category.all.length; i++)
          Expense(
              amount: (i + 1) * 100,
              category: Category.all[i].id,
              date: DateTime(2023, 1, i + 1)),
      ];
      await pumpInsights(t, items, await settings(), DateTime(2023, 1));
      for (final c in Category.all) {
        expect(find.text(c.label), findsOneWidget, reason: c.id);
      }
      expect(find.byType(LinearProgressIndicator),
          findsNWidgets(Category.all.length));
    });
  });

  group('Expense editor', () {
    testWidgets('new expense: invalid amount shows error and stays open',
        (t) async {
      final results = await openEditor(t, await settings(), null);
      expect(find.text('Add expense'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      await t.enterText(find.byType(TextField).first, 'abc');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Enter an amount, for example 120 or 49.50'),
          findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('new expense: saves parsed amount, category and trimmed note',
        (t) async {
      final results = await openEditor(t, await settings(), null);
      await t.enterText(find.byType(TextField).first, '1,234.5');
      await t.tap(find.text('Transport'));
      await t.pump();
      await t.enterText(find.byType(TextField).last, '  Bus pass  ');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(results, hasLength(1));
      final e = results.single!.expense;
      expect(results.single!.isDelete, isFalse);
      expect(e.id, isNull);
      expect(e.amount, 123450);
      expect(e.category, 'transport');
      expect(e.note, 'Bus pass');
    });

    testWidgets('new expense defaults to the first category', (t) async {
      final results = await openEditor(t, await settings(), null);
      await t.enterText(find.byType(TextField).first, '12');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(results.single!.expense.category, Category.all.first.id);
      expect(results.single!.expense.amount, 1200);
    });

    const prefill = {12000: '120', 4950: '49.50', 1234: '12.34', 5: '0.05'};
    prefill.forEach((amount, text) {
      testWidgets('edit prefills $amount as "$text" and keeps id', (t) async {
        final existing = Expense(
            id: 7,
            amount: amount,
            category: 'bills',
            date: DateTime(2025, 3, 9, 8, 30),
            note: 'Power');
        final results = await openEditor(t, await settings('€'), existing);
        expect(find.text('Edit expense'), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(find.text('€'), findsOneWidget);
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        final e = results.single!.expense;
        expect(e.id, 7);
        expect(e.amount, amount);
        expect(e.category, 'bills');
        expect(e.date, DateTime(2025, 3, 9, 8, 30));
        expect(e.note, 'Power');
      });
    });

    testWidgets('edit: delete returns the original with isDelete', (t) async {
      final existing = Expense(
          id: 3, amount: 100, category: 'fun', date: DateTime(2025, 1, 1));
      final results = await openEditor(t, await settings(), existing);
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(results.single!.isDelete, isTrue);
      expect(identical(results.single!.expense, existing), isTrue);
    });
  });
}
