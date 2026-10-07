// Play Store screenshots. Run: flutter test screenshots/store_test.dart --update-goldens
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:water_habit/main.dart';
import 'package:water_habit/store.dart';

import '../../../tool/screenshots/shot.dart';

DateTime ago(int n) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day - n);
}

String k(int n) => dayKey(ago(n));

Set<String> days(Iterable<int> n) => {for (final d in n) k(d)};

Future<AppStore> seededStore() async {
  SharedPreferences.setMockInitialValues({
    'onboarded': true,
    'goal': 2000,
    'glass': 250,
    'wake': 7 * 60,
    'sleep': 22 * 60 + 30,
    'interval': 90,
    'water': jsonEncode({
      k(0): 1250,
      k(1): 2150,
      k(2): 2000,
      k(3): 2400,
      k(4): 2250,
      k(5): 1600,
      k(6): 1850,
    }),
    'drinksDay': k(0),
    'drinks': ['250', '500', '250', '250'],
    'habits': jsonEncode([
      Habit(
              id: 1,
              name: 'Morning walk',
              reminderMinutes: 7 * 60 + 30,
              done: days([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]))
          .toJson(),
      Habit(
              id: 2,
              name: 'Read 20 pages',
              reminderMinutes: 21 * 60,
              done: days([1, 2, 3, 4, 6]))
          .toJson(),
      Habit(id: 3, name: 'Meditate', done: days([0, 1, 2, 4, 5])).toJson(),
      Habit(
              id: 4,
              name: 'Take vitamins',
              reminderMinutes: 9 * 60,
              done: days([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]))
          .toJson(),
      Habit(id: 5, name: 'Stretch', done: days([0, 2, 3])).toJson(),
      Habit(
              id: 6,
              name: 'No sugar',
              reminderMinutes: 20 * 60,
              done: days([1, 2, 3, 5]))
          .toJson(),
    ]),
  });
  return AppStore.open();
}

/// Paint real elevation shadows from the first frame. With shadows disabled
/// (the test default) elevated widgets get a solid black outline, and layers
/// cached before [shot] flips the flag keep it. [shot] turns the flag back on.
void realShadows() {
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('water', (tester) async {
    usePhone(tester);
    realShadows();
    final s = await seededStore();
    await tester.pumpWidget(WaterHabitApp(store: s));
    await tester.pumpAndSettle();
    await shot(tester, '01_water');
  });

  testWidgets('habits', (tester) async {
    usePhone(tester);
    realShadows();
    final s = await seededStore();
    await tester.pumpWidget(WaterHabitApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Habits').last);
    await tester.pumpAndSettle();
    await shot(tester, '02_habits');
  });

  testWidgets('new habit', (tester) async {
    usePhone(tester);
    realShadows();
    final s = await seededStore();
    await tester.pumpWidget(WaterHabitApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Habits').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add habit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Drink green tea');
    await tester.pumpAndSettle();
    await shot(tester, '03_new_habit');
  });

  testWidgets('settings', (tester) async {
    usePhone(tester);
    realShadows();
    final s = await seededStore();
    await tester.pumpWidget(WaterHabitApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await shot(tester, '04_reminders');
  });
}
