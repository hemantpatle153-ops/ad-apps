import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Habit {
  Habit({
    required this.id,
    required this.name,
    this.reminderMinutes,
    Set<String>? done,
  }) : done = done ?? {};

  final int id;
  String name;

  /// Minutes after midnight for the daily reminder, or null for none.
  int? reminderMinutes;

  /// Day keys on which the habit was completed.
  final Set<String> done;

  bool doneOn(DateTime d) => done.contains(dayKey(d));

  /// Consecutive completed days ending today (or yesterday if today is open).
  int streak(DateTime today) {
    var d = DateTime(today.year, today.month, today.day);
    if (!doneOn(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (doneOn(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'reminder': reminderMinutes,
        'done': done.toList(),
      };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'] as int,
        name: j['name'] as String,
        reminderMinutes: j['reminder'] as int?,
        done: Set<String>.from(j['done'] as List),
      );
}

/// Water log, goal, reminder window and habits, saved on the phone.
class AppStore extends ChangeNotifier {
  AppStore(this._p) {
    _load();
  }
  final SharedPreferences _p;

  static Future<AppStore> open() async =>
      AppStore(await SharedPreferences.getInstance());

  /// Millilitres drunk per day key.
  Map<String, int> water = {};

  /// Today's individual drinks, so the last one can be undone.
  List<int> todayDrinks = [];
  String _todayKey = '';
  List<Habit> habits = [];

  bool get onboarded => _p.getBool('onboarded') ?? false;
  set onboarded(bool v) => _p.setBool('onboarded', v);

  int get goalMl => _p.getInt('goal') ?? 2000;
  set goalMl(int v) {
    _p.setInt('goal', v);
    notifyListeners();
  }

  int get glassMl => _p.getInt('glass') ?? 250;
  set glassMl(int v) {
    _p.setInt('glass', v);
    notifyListeners();
  }

  bool get waterReminders => _p.getBool('waterReminders') ?? true;
  set waterReminders(bool v) {
    _p.setBool('waterReminders', v);
    notifyListeners();
  }

  /// Reminder window and spacing, in minutes after midnight.
  int get wakeMinutes => _p.getInt('wake') ?? 8 * 60;
  set wakeMinutes(int v) {
    _p.setInt('wake', v);
    notifyListeners();
  }

  int get sleepMinutes => _p.getInt('sleep') ?? 22 * 60;
  set sleepMinutes(int v) {
    _p.setInt('sleep', v);
    notifyListeners();
  }

  int get intervalMinutes => _p.getInt('interval') ?? 120;
  set intervalMinutes(int v) {
    _p.setInt('interval', v);
    notifyListeners();
  }

  void _load() {
    final w = _p.getString('water');
    if (w != null) {
      water = Map<String, int>.from(jsonDecode(w) as Map);
    }
    _todayKey = _p.getString('drinksDay') ?? '';
    todayDrinks = (_p.getStringList('drinks') ?? []).map(int.parse).toList();
    final h = _p.getString('habits');
    if (h != null) {
      habits = (jsonDecode(h) as List)
          .map((e) => Habit.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  void _rollDay() {
    final k = dayKey(DateTime.now());
    if (k != _todayKey) {
      _todayKey = k;
      todayDrinks = [];
    }
  }

  int mlOn(DateTime d) => water[dayKey(d)] ?? 0;
  int get todayMl => mlOn(DateTime.now());

  Future<void> addWater(int ml) async {
    _rollDay();
    final k = dayKey(DateTime.now());
    water[k] = (water[k] ?? 0) + ml;
    todayDrinks.add(ml);
    await _saveWater();
  }

  Future<void> undoWater() async {
    _rollDay();
    if (todayDrinks.isEmpty) return;
    final k = dayKey(DateTime.now());
    water[k] = ((water[k] ?? 0) - todayDrinks.removeLast()).clamp(0, 1 << 30);
    await _saveWater();
  }

  Future<void> _saveWater() async {
    // Keep a year of history.
    final cutoff = dayKey(DateTime.now().subtract(const Duration(days: 366)));
    water.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    await _p.setString('water', jsonEncode(water));
    await _p.setString('drinksDay', _todayKey);
    await _p.setStringList(
        'drinks', todayDrinks.map((e) => e.toString()).toList());
    notifyListeners();
  }

  /// Consecutive days, ending today or yesterday, that reached the goal.
  int waterStreak() {
    var d = DateTime.now();
    if (mlOn(d) < goalMl) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (mlOn(d) >= goalMl && n < 400) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  Future<Habit> addHabit(String name, int? reminder) async {
    final id = habits.fold<int>(0, (m, h) => h.id > m ? h.id : m) + 1;
    final h = Habit(id: id, name: name, reminderMinutes: reminder);
    habits.add(h);
    await saveHabits();
    return h;
  }

  Future<void> toggleHabit(Habit h, DateTime day) async {
    final k = dayKey(day);
    if (!h.done.remove(k)) h.done.add(k);
    await saveHabits();
  }

  Future<void> removeHabit(Habit h) async {
    habits.remove(h);
    await saveHabits();
  }

  Future<void> saveHabits() async {
    await _p.setString(
        'habits', jsonEncode(habits.map((h) => h.toJson()).toList()));
    notifyListeners();
  }
}

String formatMinutes(int m) {
  final h = m ~/ 60, min = m % 60;
  final suffix = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${min.toString().padLeft(2, '0')} $suffix';
}

/// Reminder times inside the waking window, every [interval] minutes.
List<int> waterReminderTimes(int wake, int sleep, int interval) {
  if (interval <= 0) return const [];
  final end = sleep > wake ? sleep : sleep + 24 * 60;
  return [
    for (var t = wake + interval; t <= end; t += interval) t % (24 * 60),
  ];
}
