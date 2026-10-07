import 'day.dart';
import 'session.dart';

/// Answered / correct / time counters.
class Tally {
  Tally([this.answered = 0, this.correct = 0, this.timeMs = 0]);
  int answered;
  int correct;
  int timeMs;

  int get wrong => answered - correct;
  double get accuracy => answered == 0 ? 0 : correct / answered;

  void add(Tally o) {
    answered += o.answered;
    correct += o.correct;
    timeMs += o.timeMs;
  }

  List<int> toJson() => [answered, correct, timeMs];

  static Tally fromJson(Object? v) {
    if (v is List && v.length >= 2) {
      int n(Object? x) => x is int && x >= 0 ? x : 0;
      final t = Tally(n(v[0]), n(v[1]), v.length > 2 ? n(v[2]) : 0);
      if (t.correct > t.answered) t.correct = t.answered;
      return t;
    }
    return Tally();
  }
}

/// Everything the Stats screen shows, kept as running totals so it stays
/// small however long the app is used.
class StatsBook {
  final Map<String, Tally> bySubject = {};

  /// Answers per IST day, kept for the last [keepDays] days.
  final Map<String, Tally> byDay = {};
  int quizzes = 0;
  int mocks = 0;
  int dailies = 0;
  int perfectDailies = 0;
  final Set<String> caDaysRead = {};

  static const keepDays = 120;

  Tally get total {
    final t = Tally();
    for (final s in bySubject.values) {
      t.add(s);
    }
    return t;
  }

  /// Adds a finished quiz. Unanswered questions count towards time only.
  void record(QuizResult r, Day today) {
    quizzes++;
    if (r.mode == QuizMode.mock) mocks++;
    if (r.mode == QuizMode.daily) {
      dailies++;
      if (r.perfect) perfectDailies++;
    }
    final dayTally = byDay.putIfAbsent(today.key, Tally.new);
    for (var i = 0; i < r.total; i++) {
      final q = r.questions[i];
      final c = r.choices[i];
      final t = bySubject.putIfAbsent(q.subject, Tally.new);
      t.timeMs += r.timesMs[i];
      dayTally.timeMs += r.timesMs[i];
      if (c == null) continue;
      t.answered++;
      dayTally.answered++;
      if (q.isCorrect(c)) {
        t.correct++;
        dayTally.correct++;
      }
    }
    _trim(today);
  }

  void _trim(Day today) {
    byDay.removeWhere((k, _) {
      final d = Day.tryParse(k);
      return d == null || today.difference(d) >= keepDays;
    });
  }

  /// Subjects with at least [minAnswered] answers and accuracy below
  /// [threshold], weakest first.
  List<String> weakSubjects({int minAnswered = 5, double threshold = 0.6}) {
    final weak = [
      for (final e in bySubject.entries)
        if (e.value.answered >= minAnswered && e.value.accuracy < threshold)
          e.key
    ];
    weak.sort((a, b) {
      final c = bySubject[a]!.accuracy.compareTo(bySubject[b]!.accuracy);
      return c != 0 ? c : a.compareTo(b);
    });
    return weak;
  }

  /// Subjects with at least one answer, most accurate first.
  List<String> strongSubjects({int minAnswered = 5}) {
    final list = [
      for (final e in bySubject.entries)
        if (e.value.answered >= minAnswered) e.key
    ];
    list.sort((a, b) {
      final c = bySubject[b]!.accuracy.compareTo(bySubject[a]!.accuracy);
      return c != 0 ? c : a.compareTo(b);
    });
    return list;
  }

  /// Answers on each of the last [days] days, oldest first.
  List<(Day, Tally)> lastDays(Day today, int days) => [
        for (var i = days - 1; i >= 0; i--)
          () {
            final d = today.addDays(-i);
            return (d, byDay[d.key] ?? Tally());
          }()
      ];

  /// Number of subjects with at least [min] answers.
  int subjectsTried({int min = 10}) =>
      bySubject.values.where((t) => t.answered >= min).length;

  Map<String, Object?> toJson() => {
        'subjects': {for (final e in bySubject.entries) e.key: e.value.toJson()},
        'days': {for (final e in byDay.entries) e.key: e.value.toJson()},
        'quizzes': quizzes,
        'mocks': mocks,
        'dailies': dailies,
        'perfectDailies': perfectDailies,
        'caDaysRead': caDaysRead.toList()..sort(),
      };

  static StatsBook fromJson(Object? json) {
    final b = StatsBook();
    if (json is! Map) return b;
    int n(Object? v) => v is int && v >= 0 ? v : 0;
    final subjects = json['subjects'];
    if (subjects is Map) {
      for (final e in subjects.entries) {
        if (e.key is String) b.bySubject[e.key as String] = Tally.fromJson(e.value);
      }
    }
    final days = json['days'];
    if (days is Map) {
      for (final e in days.entries) {
        if (e.key is String && Day.tryParse(e.key) != null) {
          b.byDay[e.key as String] = Tally.fromJson(e.value);
        }
      }
    }
    b.quizzes = n(json['quizzes']);
    b.mocks = n(json['mocks']);
    b.dailies = n(json['dailies']);
    b.perfectDailies = n(json['perfectDailies']);
    final ca = json['caDaysRead'];
    if (ca is List) {
      b.caDaysRead.addAll(ca.whereType<String>().where((s) => Day.tryParse(s) != null));
    }
    return b;
  }
}

/// XP for a finished quiz.
///
/// 10 per correct answer and 2 per wrong one (trying counts); the Daily
/// Quiz adds 20 for finishing, 30 more when perfect and 5 per streak day
/// (up to 10 days); a finished mock test adds 25.
int xpFor(QuizResult r, {int streak = 0, bool countsForStreak = false}) {
  var xp = r.correct * 10 + r.wrong * 2;
  if (r.mode == QuizMode.daily && countsForStreak) {
    xp += 20;
    if (r.perfect) xp += 30;
    xp += 5 * (streak.clamp(0, 10));
  }
  if (r.mode == QuizMode.mock) xp += 25;
  return xp;
}

class LevelInfo {
  const LevelInfo(this.level, this.xpIntoLevel, this.xpForNext);
  final int level;
  final int xpIntoLevel;

  /// XP between this level and the next.
  final int xpForNext;

  double get progress => xpForNext == 0 ? 0 : xpIntoLevel / xpForNext;

  /// Level L starts at 50 * L * (L - 1) XP: 0, 100, 300, 600, 1000 ...
  static int startOf(int level) => 50 * level * (level - 1);

  static LevelInfo fromXp(int xp) {
    if (xp < 0) xp = 0;
    var level = 1;
    while (startOf(level + 1) <= xp) {
      level++;
    }
    final start = startOf(level);
    return LevelInfo(level, xp - start, startOf(level + 1) - start);
  }
}

/// What badges are judged on.
class Progress {
  const Progress({
    required this.stats,
    required this.bestStreak,
    required this.xp,
  });
  final StatsBook stats;
  final int bestStreak;
  final int xp;
}

enum Badge {
  firstQuiz,
  streak3,
  streak7,
  streak30,
  perfectDaily,
  answered100,
  answered500,
  answered1000,
  firstMock,
  allRounder,
  caReader,
  sharpShooter,
  level5,
  level10;

  bool earned(Progress p) {
    final t = p.stats.total;
    return switch (this) {
      firstQuiz => p.stats.quizzes >= 1,
      streak3 => p.bestStreak >= 3,
      streak7 => p.bestStreak >= 7,
      streak30 => p.bestStreak >= 30,
      perfectDaily => p.stats.perfectDailies >= 1,
      answered100 => t.answered >= 100,
      answered500 => t.answered >= 500,
      answered1000 => t.answered >= 1000,
      firstMock => p.stats.mocks >= 1,
      allRounder => p.stats.subjectsTried() >= 5,
      caReader => p.stats.caDaysRead.length >= 7,
      sharpShooter => t.answered >= 100 && t.accuracy >= 0.8,
      level5 => LevelInfo.fromXp(p.xp).level >= 5,
      level10 => LevelInfo.fromXp(p.xp).level >= 10,
    };
  }

  static Set<Badge> earnedBy(Progress p) =>
      {for (final b in Badge.values) if (b.earned(p)) b};

  static Badge? parse(Object? v) =>
      Badge.values.where((b) => b.name == v).firstOrNull;
}
