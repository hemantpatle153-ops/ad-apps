import 'day.dart';
import 'models.dart';

/// A small deterministic random generator (mulberry32). dart:math's Random
/// is not promised to give the same numbers on every SDK version, and the
/// offline Daily Quiz must be the same on every phone.
class SeededRandom {
  SeededRandom(int seed) : _state = seed & 0xFFFFFFFF;
  int _state;

  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= t + _imul(t ^ (t >> 7), t | 61) & 0xFFFFFFFF;
    t &= 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  static int _imul(int a, int b) {
    final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
    final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
    return (al * bl + (((ah * bl + al * bh) << 16) & 0xFFFFFFFF)) &
        0xFFFFFFFF;
  }

  /// Uniform in [0, max).
  int nextInt(int max) {
    if (max <= 0) throw RangeError.value(max, 'max');
    return nextUint32() % max;
  }

  /// Fisher-Yates shuffle in place.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
  }
}

/// The offline Daily Quiz for [day]: [count] questions from [bank],
/// identical on every phone with the same bank.
///
/// The bank (sorted by id, so file order doesn't matter) is walked through
/// a shuffled order, [count] questions per day, so no question repeats
/// until the whole bank was used; then a new shuffle starts.
List<Question> dailyFallback(Day day, List<Question> bank, {int count = 10}) {
  final sorted = [...{for (final q in bank) q.id: q}.values]
    ..sort((a, b) => a.id.compareTo(b.id));
  final n = sorted.length;
  if (n == 0) return const [];
  final want = count < n ? count : n;
  final perms = <int, List<Question>>{};
  List<Question> perm(int cycle) => perms.putIfAbsent(cycle, () {
        final p = [...sorted];
        SeededRandom(0x52A3 ^ (cycle * 2654435761)).shuffle(p);
        return p;
      });
  final out = <Question>[];
  final ids = <String>{};
  // Day index can be negative for dates before 1970; keep positions >= 0.
  var pos = (day.index + 1000000) * want;
  while (out.length < want) {
    final q = perm(pos ~/ n)[pos % n];
    if (ids.add(q.id)) out.add(q);
    pos++;
  }
  return out;
}

/// Which questions a practice session may use.
class PracticeFilter {
  const PracticeFilter({
    this.subject,
    this.exam,
    this.difficulty,
    this.pyqOnly = false,
  });
  final String? subject;
  final String? exam;
  final Difficulty? difficulty;
  final bool pyqOnly;

  bool matches(Question q) =>
      (subject == null || q.subject == subject) &&
      (exam == null || q.exams.contains(exam)) &&
      (difficulty == null || q.difficulty == difficulty) &&
      (!pyqOnly || q.isPyq);

  List<Question> apply(Iterable<Question> pool) =>
      [for (final q in pool) if (matches(q)) q];
}

class PickResult {
  const PickResult(this.questions, this.seen, {required this.recycled});
  final List<Question> questions;

  /// The updated set of seen ids to store.
  final Set<String> seen;

  /// True when every question of the pool had been seen and the cycle
  /// started again.
  final bool recycled;
}

/// Picks up to [count] questions from [pool], preferring ones not in
/// [seen]. Questions are not repeated until the pool is exhausted; then the
/// pool's ids are forgotten and a new round begins, with this session's
/// questions already counted as seen in it.
PickResult pickWithoutRepeats(
  List<Question> pool,
  int count,
  Set<String> seen,
  SeededRandom random,
) {
  final unique = [...{for (final q in pool) q.id: q}.values];
  final want = count < unique.length ? count : unique.length;
  final unseen = [for (final q in unique) if (!seen.contains(q.id)) q];
  random.shuffle(unseen);
  if (unseen.length >= want) {
    final pick = unseen.take(want).toList();
    return PickResult(pick, {...seen, for (final q in pick) q.id},
        recycled: false);
  }
  final rest = [for (final q in unique) if (seen.contains(q.id)) q];
  random.shuffle(rest);
  final pick = [...unseen, ...rest.take(want - unseen.length)];
  random.shuffle(pick);
  final poolIds = {for (final q in unique) q.id};
  final newSeen = {
    for (final id in seen) if (!poolIds.contains(id)) id,
    for (final q in pick) q.id,
  };
  return PickResult(pick, newSeen, recycled: true);
}

/// A mock test: [count] questions for [exam] (any exam when null), not
/// repeated until the pool is used up, grouped into sections by subject in
/// [kSubjects] order.
PickResult buildMockTest(
  List<Question> pool,
  int count,
  Set<String> seen,
  SeededRandom random, {
  String? exam,
}) {
  final eligible = PracticeFilter(exam: exam).apply(pool);
  final r = pickWithoutRepeats(eligible, count, seen, random);
  final order = {for (var i = 0; i < kSubjects.length; i++) kSubjects[i]: i};
  final indexed = [for (var i = 0; i < r.questions.length; i++) (i, r.questions[i])]
    ..sort((a, b) {
      final c = (order[a.$2.subject] ?? 99).compareTo(order[b.$2.subject] ?? 99);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return PickResult([for (final e in indexed) e.$2], r.seen,
      recycled: r.recycled);
}
