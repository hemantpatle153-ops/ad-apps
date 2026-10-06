import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:water_habit/habits_view.dart';
import 'package:water_habit/settings_screen.dart';
import 'package:water_habit/store.dart';
import 'package:water_habit/water_view.dart';

import 'support/gen.dart';

Future<AppStore> storeWith([Map<String, Object> v = const {}]) async {
  SharedPreferences.setMockInitialValues(v);
  return AppStore(await SharedPreferences.getInstance());
}

Widget host(AppStore s, Widget Function(AppStore) child) => MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(listenable: s, builder: (_, __) => child(s)),
      ),
    );

DateTime get today {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

void main() {
  group('WaterView', () {
    testWidgets('shows progress and remaining amount', (t) async {
      final s = await storeWith({'water': jsonEncode({dayKey(today): 500})});
      await t.pumpWidget(host(s, (s) => WaterView(store: s)));
      expect(find.text('500 ml'), findsOneWidget);
      expect(find.text('of 2000 ml'), findsOneWidget);
      expect(find.text('1500 ml to go. Streak: 0 days'), findsOneWidget);
      final p = t.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      expect(p.value, closeTo(.25, 1e-9));
    });

    testWidgets('glass buttons add water and undo appears', (t) async {
      final s = await storeWith({'glass': 300});
      await t.pumpWidget(host(s, (s) => WaterView(store: s)));
      expect(find.textContaining('Undo'), findsNothing);
      await t.tap(find.text('+300 ml'));
      await t.pumpAndSettle();
      expect(s.todayMl, 300);
      await t.tap(find.text('+600 ml'));
      await t.pumpAndSettle();
      expect(s.todayMl, 900);
      expect(find.text('Undo 600 ml'), findsOneWidget);
      await t.tap(find.text('Undo 600 ml'));
      await t.pumpAndSettle();
      expect(s.todayMl, 300);
      expect(find.text('Undo 300 ml'), findsOneWidget);
    });

    testWidgets('reaching the goal shows the celebration dialog', (t) async {
      final s = await storeWith({
        'water': jsonEncode({
          dayKey(today): 1800,
          dayKey(daysBefore(today, 1)): 2000,
        }),
      });
      await t.pumpWidget(host(s, (s) => WaterView(store: s)));
      await t.tap(find.text('+250 ml'));
      await t.pumpAndSettle();
      expect(find.text('Goal reached!'), findsOneWidget);
      expect(find.text('You drank 2050 ml today. Streak: 2 days.'),
          findsOneWidget);
      await t.tap(find.text('Nice'));
      await t.pumpAndSettle();
      expect(find.text('Goal reached!'), findsNothing);
      expect(find.text('Goal reached. Streak: 2 days'), findsOneWidget);
    });

    for (final (input, added) in [
      ('330', 330),
      (' 75 ', 75),
      ('5000', 5000),
      ('5001', 0),
      ('0', 0),
      ('-50', 0),
      ('abc', 0),
    ]) {
      testWidgets('custom amount "$input" adds $added', (t) async {
        final s = await storeWith();
        await t.pumpWidget(host(s, (s) => WaterView(store: s)));
        await t.tap(find.text('Custom'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), input);
        await t.tap(find.text('Add'));
        await t.pumpAndSettle();
        expect(s.todayMl, added);
      });
    }

    testWidgets('custom dialog cancel adds nothing', (t) async {
      final s = await storeWith();
      await t.pumpWidget(host(s, (s) => WaterView(store: s)));
      await t.tap(find.text('Custom'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '400');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(s.todayMl, 0);
    });

    testWidgets('weekly chart labels show litres per day', (t) async {
      final s = await storeWith({
        'water': jsonEncode({
          dayKey(today): 1250,
          dayKey(daysBefore(today, 3)): 3000,
        }),
      });
      await t.pumpWidget(host(s, (s) => WaterView(store: s)));
      expect(find.text('1.3L'), findsOneWidget);
      expect(find.text('3.0L'), findsOneWidget);
      expect(find.text('0.0L'), findsNWidgets(5));
    });
  });

  group('HabitsView', () {
    testWidgets('empty state', (t) async {
      final s = await storeWith();
      await t.pumpWidget(host(s, (s) => HabitsView(store: s)));
      expect(find.textContaining('No habits yet'), findsOneWidget);
      expect(find.text('Add habit'), findsOneWidget);
    });

    testWidgets('lists habits with streak and reminder', (t) async {
      final s = await storeWith({
        'habits': jsonEncode([
          Habit(id: 1, name: 'Walk', reminderMinutes: 1230, done: {
            dayKey(daysBefore(today, 1)),
            dayKey(daysBefore(today, 2)),
          }).toJson(),
          Habit(id: 2, name: 'Read').toJson(),
        ]),
      });
      await t.pumpWidget(host(s, (s) => HabitsView(store: s)));
      expect(find.text('Walk'), findsOneWidget);
      expect(find.text('2 day streak · reminder 8:30 PM'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('0 day streak'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });

    testWidgets('checkbox toggles today', (t) async {
      final s = await storeWith({
        'habits': jsonEncode([Habit(id: 1, name: 'Walk').toJson()]),
      });
      await t.pumpWidget(host(s, (s) => HabitsView(store: s)));
      await t.tap(find.byType(Checkbox));
      await t.pumpAndSettle();
      expect(s.habits.single.doneOn(today), isTrue);
      expect(find.text('1 day streak'), findsOneWidget);
      await t.tap(find.byType(Checkbox));
      await t.pumpAndSettle();
      expect(s.habits.single.doneOn(today), isFalse);
    });

    testWidgets('tapping a past day circle marks it', (t) async {
      final s = await storeWith({
        'habits': jsonEncode([Habit(id: 1, name: 'Walk').toJson()]),
      });
      await t.pumpWidget(host(s, (s) => HabitsView(store: s)));
      await t.tap(find.byIcon(Icons.circle_outlined).first);
      await t.pumpAndSettle();
      expect(s.habits.single.doneOn(daysBefore(today, 6)), isTrue);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('new habit dialog can be cancelled', (t) async {
      final s = await storeWith();
      await t.pumpWidget(host(s, (s) => HabitsView(store: s)));
      await t.tap(find.text('Add habit'));
      await t.pumpAndSettle();
      expect(find.text('New habit'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Stretch');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('New habit'), findsNothing);
      expect(s.habits, isEmpty);
    });

    testWidgets('edit dialog is prefilled and can be cancelled', (t) async {
      final s = await storeWith({
        'habits': jsonEncode(
            [Habit(id: 1, name: 'Walk', reminderMinutes: 450).toJson()]),
      });
      await t.pumpWidget(host(s, (s) => HabitsView(store: s)));
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      expect(find.text('Edit habit'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Walk'), findsOneWidget);
      expect(find.text('7:30 AM'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Run');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(s.habits.single.name, 'Walk');
      expect(s.habits.single.reminderMinutes, 450);
    });

    testWidgets('delete dialog can be cancelled', (t) async {
      final s = await storeWith({
        'habits': jsonEncode([Habit(id: 1, name: 'Walk').toJson()]),
      });
      await t.pumpWidget(host(s, (s) => HabitsView(store: s)));
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete "Walk"?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(s.habits.length, 1);
    });
  });

  group('SettingsScreen', () {
    Widget app(AppStore s) => MaterialApp(home: SettingsScreen(store: s));

    testWidgets('shows current settings', (t) async {
      final s = await storeWith({'wake': 7 * 60 + 15, 'sleep': 23 * 60, 'goal': 3000});
      await t.pumpWidget(app(s));
      await t.pump();
      expect(find.text('3000 ml'), findsOneWidget);
      expect(find.text('250 ml'), findsOneWidget);
      expect(find.text('7:15 AM'), findsOneWidget);
      expect(find.text('11:00 PM'), findsOneWidget);
      expect(find.text('2 h'), findsOneWidget);
    });

    testWidgets('unknown stored values fall back in dropdowns', (t) async {
      final s = await storeWith({'goal': 1234, 'glass': 99, 'interval': 45});
      await t.pumpWidget(app(s));
      await t.pump();
      expect(find.text('2000 ml'), findsOneWidget);
      expect(find.text('250 ml'), findsOneWidget);
      expect(find.text('2 h'), findsOneWidget);
    });

    testWidgets('picking a goal saves it', (t) async {
      final s = await storeWith();
      await t.pumpWidget(app(s));
      await t.pump();
      await t.tap(find.text('2000 ml'));
      await t.pumpAndSettle();
      await t.tap(find.text('3500 ml').last);
      await t.pumpAndSettle();
      expect(s.goalMl, 3500);
      expect(find.text('3500 ml'), findsOneWidget);
    });

    testWidgets('picking a glass size saves it', (t) async {
      final s = await storeWith();
      await t.pumpWidget(app(s));
      await t.pump();
      await t.tap(find.text('250 ml'));
      await t.pumpAndSettle();
      await t.tap(find.text('500 ml').last);
      await t.pumpAndSettle();
      expect(s.glassMl, 500);
    });

    testWidgets('reminder rows disabled when reminders are off', (t) async {
      final s = await storeWith({'waterReminders': false, 'interval': 90});
      await t.pumpWidget(app(s));
      await t.pump();
      final wake = t.widget<ListTile>(find.widgetWithText(ListTile, 'Wake up'));
      expect(wake.enabled, isFalse);
      expect(find.text('1.5 h'), findsOneWidget);
      final dd = t.widget<DropdownButton<int>>(find.byType(DropdownButton<int>).last);
      expect(dd.onChanged, isNull);
    });
  });
}
