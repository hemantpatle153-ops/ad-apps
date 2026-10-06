import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:water_habit/store.dart';

import 'support/gen.dart';

Future<(AppStore, SharedPreferences)> openWith(
    [Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  final p = await SharedPreferences.getInstance();
  return (AppStore(p), p);
}

DateTime get today {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String ago(int n) => dayKey(daysBefore(today, n));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaults on a fresh install', () {
    final defaults = <String, Object Function(AppStore)>{
      'goalMl 2000': (s) => s.goalMl == 2000,
      'glassMl 250': (s) => s.glassMl == 250,
      'waterReminders on': (s) => s.waterReminders,
      'wake 8:00': (s) => s.wakeMinutes == 480,
      'sleep 22:00': (s) => s.sleepMinutes == 1320,
      'interval 120': (s) => s.intervalMinutes == 120,
      'not onboarded': (s) => !s.onboarded,
      'no water': (s) => s.water.isEmpty && s.todayMl == 0,
      'no drinks': (s) => s.todayDrinks.isEmpty,
      'no habits': (s) => s.habits.isEmpty,
      'streak 0': (s) => s.waterStreak() == 0,
    };
    defaults.forEach((name, check) {
      test(name, () async {
        final (s, _) = await openWith();
        expect(check(s), isTrue);
      });
    });
  });

  group('int settings persist and notify', () {
    final settings = <String, (String, void Function(AppStore, int), int Function(AppStore))>{
      'goal': ('goal', (s, v) => s.goalMl = v, (s) => s.goalMl),
      'glass': ('glass', (s, v) => s.glassMl = v, (s) => s.glassMl),
      'wake': ('wake', (s, v) => s.wakeMinutes = v, (s) => s.wakeMinutes),
      'sleep': ('sleep', (s, v) => s.sleepMinutes = v, (s) => s.sleepMinutes),
      'interval': ('interval', (s, v) => s.intervalMinutes = v, (s) => s.intervalMinutes),
    };
    const values = [0, 1, 60, 150, 500, 1439, 3500];
    settings.forEach((name, spec) {
      final (key, set, get) = spec;
      for (final v in values) {
        test('$name = $v', () async {
          final (s, p) = await openWith();
          var notified = 0;
          s.addListener(() => notified++);
          set(s, v);
          expect(get(s), v);
          expect(p.getInt(key), v);
          expect(notified, 1);
          // A fresh store over the same prefs sees the value.
          expect(get(AppStore(p)), v);
        });
      }
    });
  });

  group('bool settings', () {
    for (final v in [true, false]) {
      test('waterReminders = $v persists and notifies', () async {
        final (s, p) = await openWith();
        var notified = 0;
        s.addListener(() => notified++);
        s.waterReminders = v;
        expect(s.waterReminders, v);
        expect(p.getBool('waterReminders'), v);
        expect(notified, 1);
      });
      test('onboarded = $v persists without notifying', () async {
        final (s, p) = await openWith();
        var notified = 0;
        s.addListener(() => notified++);
        s.onboarded = v;
        expect(s.onboarded, v);
        expect(p.getBool('onboarded'), v);
        expect(notified, 0);
      });
    }
  });

  group('loads saved state', () {
    test('water map', () async {
      final (s, _) = await openWith({
        'water': jsonEncode({ago(0): 750, ago(1): 2100}),
      });
      expect(s.todayMl, 750);
      expect(s.mlOn(daysBefore(today, 1)), 2100);
      expect(s.mlOn(daysBefore(today, 2)), 0);
    });
    test('todays drinks', () async {
      final (s, _) = await openWith({
        'drinksDay': ago(0),
        'drinks': ['250', '500', '100'],
      });
      expect(s.todayDrinks, [250, 500, 100]);
    });
    test('habits list', () async {
      final h = Habit(id: 4, name: 'Walk', reminderMinutes: 600, done: {ago(0)});
      final (s, _) = await openWith({
        'habits': jsonEncode([h.toJson()]),
      });
      expect(s.habits.single.id, 4);
      expect(s.habits.single.name, 'Walk');
      expect(s.habits.single.reminderMinutes, 600);
      expect(s.habits.single.doneOn(today), isTrue);
    });
    test('settings', () async {
      final (s, _) = await openWith({
        'goal': 3000,
        'glass': 350,
        'wake': 360,
        'sleep': 1380,
        'interval': 90,
        'waterReminders': false,
        'onboarded': true,
      });
      expect([s.goalMl, s.glassMl, s.wakeMinutes, s.sleepMinutes, s.intervalMinutes],
          [3000, 350, 360, 1380, 90]);
      expect(s.waterReminders, isFalse);
      expect(s.onboarded, isTrue);
    });
  });

  group('addWater sums into today', () {
    final r = Random(3);
    for (var n = 0; n < 25; n++) {
      final drinks = [for (var i = 0; i < 1 + r.nextInt(8); i++) 50 + r.nextInt(600)];
      test('#$n drinks $drinks', () async {
        final (s, p) = await openWith();
        var notified = 0;
        s.addListener(() => notified++);
        for (final d in drinks) {
          await s.addWater(d);
        }
        final total = drinks.fold<int>(0, (a, b) => a + b);
        expect(s.todayMl, total);
        expect(s.todayDrinks, drinks);
        expect(notified, drinks.length);
        expect(jsonDecode(p.getString('water')!)[ago(0)], total);
        expect(p.getStringList('drinks'), drinks.map((e) => '$e').toList());
        expect(p.getString('drinksDay'), ago(0));
        // Reload keeps everything.
        final again = AppStore(p);
        expect(again.todayMl, total);
        expect(again.todayDrinks, drinks);
      });
    }
  });

  group('undoWater removes the last drink', () {
    final r = Random(8);
    for (var n = 0; n < 20; n++) {
      final drinks = [for (var i = 0; i < 1 + r.nextInt(6); i++) 50 + r.nextInt(500)];
      final undos = r.nextInt(drinks.length + 3);
      test('#$n drinks $drinks undo x$undos', () async {
        final (s, _) = await openWith();
        for (final d in drinks) {
          await s.addWater(d);
        }
        for (var i = 0; i < undos; i++) {
          await s.undoWater();
        }
        final kept = drinks.take(max(0, drinks.length - undos)).toList();
        expect(s.todayDrinks, kept);
        expect(s.todayMl, kept.fold<int>(0, (a, b) => a + b));
      });
    }
  });

  group('undo edge cases', () {
    test('undo with no drinks is a no-op and does not notify', () async {
      final (s, _) = await openWith({'water': jsonEncode({ago(0): 400})});
      var notified = 0;
      s.addListener(() => notified++);
      await s.undoWater();
      expect(s.todayMl, 400);
      expect(notified, 0);
    });
    test('undo never goes below zero', () async {
      final (s, _) = await openWith({
        'water': jsonEncode({ago(0): 100}),
        'drinksDay': ago(0),
        'drinks': ['300'],
      });
      await s.undoWater();
      expect(s.todayMl, 0);
      expect(s.todayDrinks, isEmpty);
    });
  });

  group('drinks from another day are dropped', () {
    for (final stale in [1, 2, 30]) {
      test('drinksDay $stale days ago', () async {
        final (s, p) = await openWith({
          'water': jsonEncode({ago(stale): 900}),
          'drinksDay': ago(stale),
          'drinks': ['400', '500'],
        });
        await s.undoWater();
        expect(s.todayDrinks, isEmpty);
        expect(s.mlOn(daysBefore(today, stale)), 900);
        await s.addWater(200);
        expect(s.todayDrinks, [200]);
        expect(p.getString('drinksDay'), ago(0));
      });
    }
    test('empty drinksDay key', () async {
      final (s, _) = await openWith({'drinks': ['1', '2']});
      await s.addWater(10);
      expect(s.todayDrinks, [10]);
    });
  });

  group('history older than a year is pruned on save', () {
    final cases = <int, bool>{
      0: true,
      1: true,
      100: true,
      300: true,
      364: true,
      380: false,
      400: false,
      1000: false,
    };
    cases.forEach((age, kept) {
      test('$age days old kept=$kept', () async {
        final (s, p) = await openWith({'water': jsonEncode({ago(age): 1234})});
        await s.addWater(1);
        final saved = jsonDecode(p.getString('water')!) as Map;
        expect(saved.containsKey(ago(age)), kept);
        expect(s.water.containsKey(ago(age)), kept);
      });
    });
  });

  group('waterStreak', () {
    for (var n = 0; n <= 12; n++) {
      test('$n goal days ending today', () async {
        final (s, _) = await openWith({
          'water': jsonEncode({for (var i = 0; i < n; i++) ago(i): 2000}),
        });
        expect(s.waterStreak(), n);
      });
      test('$n goal days ending yesterday', () async {
        final (s, _) = await openWith({
          'water': jsonEncode({
            ago(0): 1999,
            for (var i = 1; i <= n; i++) ago(i): 2500,
          }),
        });
        expect(s.waterStreak(), n);
      });
    }
    for (final goal in [1500, 2500, 4000]) {
      test('respects a goal of $goal', () async {
        final (s, _) = await openWith({
          'goal': goal,
          'water': jsonEncode({
            ago(0): goal,
            ago(1): goal + 1,
            ago(2): goal - 1,
            ago(3): goal,
          }),
        });
        expect(s.waterStreak(), 2);
      });
    }
    test('caps at 400 days', () async {
      final (s, _) = await openWith();
      for (var i = 0; i < 450; i++) {
        s.water[ago(i)] = 3000;
      }
      expect(s.waterStreak(), 400);
    });
  });

  group('habits', () {
    test('ids increase from the current max', () async {
      final (s, _) = await openWith({
        'habits': jsonEncode([
          Habit(id: 3, name: 'a').toJson(),
          Habit(id: 9, name: 'b').toJson(),
        ]),
      });
      final h = await s.addHabit('c', null);
      expect(h.id, 10);
      expect((await s.addHabit('d', 600)).id, 11);
    });
    for (var n = 1; n <= 6; n++) {
      test('adding $n habits gives ids 1..$n and persists', () async {
        final (s, p) = await openWith();
        for (var i = 0; i < n; i++) {
          await s.addHabit('h$i', i.isEven ? i * 60 : null);
        }
        expect(s.habits.map((h) => h.id), [for (var i = 1; i <= n; i++) i]);
        final again = AppStore(p);
        expect(again.habits.map((h) => h.name), [for (var i = 0; i < n; i++) 'h$i']);
        expect(again.habits.map((h) => h.reminderMinutes),
            [for (var i = 0; i < n; i++) i.isEven ? i * 60 : null]);
      });
    }
    test('toggle marks and unmarks a day', () async {
      final (s, p) = await openWith();
      final h = await s.addHabit('Walk', null);
      await s.toggleHabit(h, today);
      expect(h.doneOn(today), isTrue);
      expect(AppStore(p).habits.single.doneOn(today), isTrue);
      await s.toggleHabit(h, DateTime(today.year, today.month, today.day, 18));
      expect(h.doneOn(today), isFalse);
      expect(AppStore(p).habits.single.done, isEmpty);
    });
    test('toggling past days builds a streak', () async {
      final (s, _) = await openWith();
      final h = await s.addHabit('Read', 1200);
      for (var i = 1; i <= 5; i++) {
        await s.toggleHabit(h, daysBefore(today, i));
      }
      expect(h.streak(today), 5);
      await s.toggleHabit(h, today);
      expect(h.streak(today), 6);
      await s.toggleHabit(h, daysBefore(today, 3));
      expect(h.streak(today), 3);
    });
    test('remove deletes and persists; ids are not reused below max', () async {
      final (s, p) = await openWith();
      final a = await s.addHabit('a', null);
      final b = await s.addHabit('b', null);
      await s.removeHabit(a);
      expect(s.habits, [b]);
      expect(AppStore(p).habits.map((h) => h.name), ['b']);
      expect((await s.addHabit('c', null)).id, 3);
    });
    test('removing the max id lets the next habit take it', () async {
      final (s, _) = await openWith();
      await s.addHabit('a', null);
      final b = await s.addHabit('b', null);
      await s.removeHabit(b);
      expect((await s.addHabit('c', null)).id, 2);
    });
    test('every habit mutation notifies', () async {
      final (s, _) = await openWith();
      var notified = 0;
      s.addListener(() => notified++);
      final h = await s.addHabit('a', null);
      await s.toggleHabit(h, today);
      await s.removeHabit(h);
      await s.saveHabits();
      expect(notified, 4);
    });
  });
}
