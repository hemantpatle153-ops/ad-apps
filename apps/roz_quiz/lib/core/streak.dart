import 'day.dart';

/// Streak numbers derived from the set of IST days on which the Daily Quiz
/// was finished. Nothing is stored except that set, so a phone whose clock
/// jumps around never corrupts the streak: it is recomputed every time.
class StreakInfo {
  const StreakInfo({
    required this.current,
    required this.best,
    required this.playedToday,
    required this.totalDays,
  });

  /// Consecutive days up to today, or up to yesterday when today is not
  /// played yet (the streak is still alive until IST midnight).
  final int current;
  final int best;
  final bool playedToday;
  final int totalDays;

  /// Alive but lost at midnight unless today's quiz is played.
  bool get atRisk => !playedToday && current > 0;

  static StreakInfo compute(Iterable<Day> played, Day today) {
    // Days after "today" can only come from a clock that was set ahead;
    // they are ignored rather than trusted.
    final days = {for (final d in played) if (!d.isAfter(today)) d.index};
    final playedToday = days.contains(today.index);
    var current = 0;
    var cursor = playedToday ? today.index : today.index - 1;
    while (days.contains(cursor)) {
      current++;
      cursor--;
    }
    final sorted = days.toList()..sort();
    var best = 0, run = 0;
    int? prev;
    for (final i in sorted) {
      run = (prev != null && i == prev + 1) ? run + 1 : 1;
      if (run > best) best = run;
      prev = i;
    }
    return StreakInfo(
      current: current,
      best: best,
      playedToday: playedToday,
      totalDays: days.length,
    );
  }
}

/// One cell of the calendar heatmap.
class HeatCell {
  const HeatCell(this.day, this.level, {this.future = false});
  final Day day;

  /// 0 = not played, 1-4 = played, darker for better scores.
  final int level;
  final bool future;
}

/// Weeks (Monday to Sunday) ending with the week of [today], oldest first,
/// for a GitHub-style heatmap. [scores] maps a day to the fraction of the
/// Daily Quiz answered correctly (0-1).
List<List<HeatCell>> heatmapWeeks(
    Day today, int weeks, Map<Day, double> scores) {
  final monday = today.addDays(1 - today.weekday);
  final start = monday.addDays(-7 * (weeks - 1));
  return [
    for (var w = 0; w < weeks; w++)
      [
        for (var d = 0; d < 7; d++)
          () {
            final day = start.addDays(w * 7 + d);
            final s = scores[day];
            return HeatCell(day, s == null ? 0 : heatLevel(s),
                future: day.isAfter(today));
          }()
      ]
  ];
}

/// Played days are at least level 1, even with no correct answer.
int heatLevel(double fraction) {
  if (fraction.isNaN || fraction < 0.25) return 1;
  if (fraction < 0.5) return 2;
  if (fraction < 0.8) return 3;
  return 4;
}
