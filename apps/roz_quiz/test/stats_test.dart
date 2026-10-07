import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/session.dart';
import 'package:roz_quiz/core/stats.dart';

import 'support/harness.dart';

/// A finished quiz: pattern of c (correct), w (wrong), - (blank).
QuizResult result(String pattern,
    {QuizMode mode = QuizMode.practice, String subject = 'gk', List<String>? subjects, int timeMs = 1000}) {
  final qs = <Question>[
    for (var i = 0; i < pattern.length; i++)
      makeQ(answer: i % 4, subject: subjects == null ? subject : subjects[i % subjects.length])
  ];
  return QuizResult.score(
    mode: mode,
    questions: qs,
    choices: [
      for (var i = 0; i < pattern.length; i++)
        switch (pattern[i]) {
          'c' => qs[i].answer,
          'w' => (qs[i].answer + 1) % 4,
          _ => null,
        }
    ],
    timesMs: List.filled(pattern.length, timeMs),
  );
}

final today = Day(2026, 10, 7);

void main() {
  group('Tally', () {
    test('defaults', () {
      final t = Tally();
      expect(t.answered, 0);
      expect(t.accuracy, 0);
      expect(t.wrong, 0);
    });
    test('accuracy and wrong', () {
      final t = Tally(10, 7, 500);
      expect(t.accuracy, 0.7);
      expect(t.wrong, 3);
    });
    test('add', () {
      final t = Tally(1, 1, 10)..add(Tally(3, 1, 5));
      expect(t.toJson(), [4, 2, 15]);
    });
    test('JSON round trip', () {
      final t = Tally.fromJson(Tally(5, 3, 99).toJson());
      expect(t.toJson(), [5, 3, 99]);
    });
    final bad = <Object?>[null, 'x', 3, [], [1], {'a': 1}];
    for (final b in bad) {
      test('fromJson($b) is empty', () => expect(Tally.fromJson(b).toJson(), [0, 0, 0]));
    }
    test('fromJson without time', () => expect(Tally.fromJson([4, 2]).toJson(), [4, 2, 0]));
    test('fromJson clamps negatives and junk', () {
      expect(Tally.fromJson([-4, 'x', 1.5]).toJson(), [0, 0, 0]);
    });
    test('fromJson caps correct at answered', () {
      expect(Tally.fromJson([3, 9, 0]).toJson(), [3, 3, 0]);
    });
  });

  group('StatsBook.record', () {
    test('counts quizzes by mode', () {
      final b = StatsBook()
        ..record(result('cc', mode: QuizMode.daily), today)
        ..record(result('cw', mode: QuizMode.daily), today)
        ..record(result('c', mode: QuizMode.mock), today)
        ..record(result('c'), today);
      expect(b.quizzes, 4);
      expect(b.dailies, 2);
      expect(b.perfectDailies, 1);
      expect(b.mocks, 1);
    });
    test('subject tallies', () {
      final b = StatsBook()..record(result('cw-c', subjects: ['polity', 'maths']), today);
      expect(b.bySubject['polity']!.toJson(), [1, 1, 2000]);
      expect(b.bySubject['maths']!.toJson(), [2, 1, 2000]);
      expect(b.total.toJson(), [3, 2, 4000]);
    });
    test('blank answers add time only', () {
      final b = StatsBook()..record(result('---'), today);
      expect(b.bySubject['gk']!.toJson(), [0, 0, 3000]);
    });
    test('day tallies', () {
      final b = StatsBook()
        ..record(result('cc'), today)
        ..record(result('w'), today)
        ..record(result('c'), today.addDays(-1));
      expect(b.byDay[today.key]!.toJson(), [3, 2, 3000]);
      expect(b.byDay[today.addDays(-1).key]!.toJson(), [1, 1, 1000]);
    });
    test('old days are trimmed after keepDays', () {
      final b = StatsBook()..record(result('c'), today.addDays(-200));
      b.record(result('c'), today);
      expect(b.byDay.keys, [today.key]);
    });
    test('day exactly keepDays-1 old is kept', () {
      final b = StatsBook()..record(result('c'), today.addDays(-(StatsBook.keepDays - 1)));
      b.record(result('c'), today);
      expect(b.byDay.length, 2);
    });
    test('day exactly keepDays old is dropped', () {
      final b = StatsBook()..record(result('c'), today.addDays(-StatsBook.keepDays));
      b.record(result('c'), today);
      expect(b.byDay.length, 1);
    });
    test('subject totals are never trimmed', () {
      final b = StatsBook()..record(result('c'), today.addDays(-500));
      b.record(result('c'), today);
      expect(b.total.answered, 2);
    });
  });

  group('weak and strong subjects', () {
    StatsBook book(Map<String, (int, int)> data) {
      final b = StatsBook();
      data.forEach((k, v) => b.bySubject[k] = Tally(v.$1, v.$2));
      return b;
    }

    test('weak: below 60% with at least 5 answers, weakest first', () {
      final b = book({'gk': (10, 9), 'polity': (10, 5), 'maths': (10, 2), 'english': (4, 0)});
      expect(b.weakSubjects(), ['maths', 'polity']);
    });
    test('exactly 60% is not weak', () {
      expect(book({'gk': (10, 6)}).weakSubjects(), isEmpty);
    });
    test('ties are sorted by name', () {
      expect(book({'polity': (10, 1), 'economy': (10, 1)}).weakSubjects(), ['economy', 'polity']);
    });
    test('custom thresholds', () {
      final b = book({'gk': (3, 0)});
      expect(b.weakSubjects(), isEmpty);
      expect(b.weakSubjects(minAnswered: 3), ['gk']);
      expect(book({'gk': (10, 7)}).weakSubjects(threshold: 0.8), ['gk']);
    });
    test('strong: most accurate first', () {
      final b = book({'gk': (10, 9), 'polity': (10, 5), 'maths': (10, 10), 'x': (2, 2)});
      expect(b.strongSubjects(), ['maths', 'gk', 'polity']);
    });
    test('subjectsTried', () {
      final b = book({'gk': (10, 1), 'polity': (9, 1), 'maths': (30, 1)});
      expect(b.subjectsTried(), 2);
      expect(b.subjectsTried(min: 1), 3);
    });
  });

  group('lastDays', () {
    test('oldest first, with empty days filled', () {
      final b = StatsBook()..record(result('cc'), today.addDays(-2));
      final days = b.lastDays(today, 4);
      expect(days.map((e) => e.$1), [for (var i = 3; i >= 0; i--) today.addDays(-i)]);
      expect(days.map((e) => e.$2.answered), [0, 2, 0, 0]);
    });
    test('zero days', () => expect(StatsBook().lastDays(today, 0), isEmpty));
  });

  group('StatsBook JSON', () {
    test('round trip', () {
      final b = StatsBook()
        ..record(result('cwc', mode: QuizMode.daily, subjects: ['gk', 'maths']), today)
        ..record(result('c', mode: QuizMode.mock), today.addDays(-3))
        ..caDaysRead.addAll(['2026-10-07', '2026-10-01']);
      final json = jsonDecode(jsonEncode(b.toJson()));
      final c = StatsBook.fromJson(json);
      expect(jsonEncode(c.toJson()), jsonEncode(b.toJson()));
      expect(c.quizzes, 2);
      expect(c.mocks, 1);
      expect(c.dailies, 1);
      expect(c.caDaysRead, {'2026-10-07', '2026-10-01'});
    });
    test('caDaysRead is sorted in JSON', () {
      final b = StatsBook()..caDaysRead.addAll(['2026-10-07', '2026-01-01', '2026-05-05']);
      expect(b.toJson()['caDaysRead'], ['2026-01-01', '2026-05-05', '2026-10-07']);
    });
    for (final bad in <Object?>[null, 'x', 5, [], <String, Object?>{}]) {
      test('fromJson($bad) gives an empty book', () {
        final b = StatsBook.fromJson(bad);
        expect(b.quizzes, 0);
        expect(b.bySubject, isEmpty);
      });
    }
    test('junk inside is skipped', () {
      final b = StatsBook.fromJson({
        'subjects': {'gk': [3, 2, 1], 'bad': 'x'},
        'days': {'2026-10-07': [1, 1], 'not-a-day': [1, 1], '2026-02-30': [1, 1]},
        'quizzes': -3,
        'mocks': 'many',
        'dailies': 2,
        'caDaysRead': ['2026-10-07', 'junk', 5],
      });
      expect(b.bySubject['gk']!.toJson(), [3, 2, 1]);
      expect(b.bySubject['bad']!.toJson(), [0, 0, 0]);
      expect(b.byDay.keys, ['2026-10-07']);
      expect(b.quizzes, 0);
      expect(b.mocks, 0);
      expect(b.dailies, 2);
      expect(b.caDaysRead, {'2026-10-07'});
    });
  });

  group('xpFor', () {
    final cases = <(String, QuizMode, int, bool, int)>[
      ('cccc', QuizMode.practice, 0, false, 40),
      ('ccww', QuizMode.practice, 0, false, 24),
      ('----', QuizMode.practice, 0, false, 0),
      ('wwww', QuizMode.practice, 0, false, 8),
      ('cccc', QuizMode.daily, 0, false, 40),
      ('cccc', QuizMode.daily, 0, true, 90),
      ('cccw', QuizMode.daily, 0, true, 52),
      ('cccc', QuizMode.daily, 1, true, 95),
      ('cccc', QuizMode.daily, 10, true, 140),
      ('cccc', QuizMode.daily, 50, true, 140),
      ('cccc', QuizMode.daily, -5, true, 90),
      ('cc--', QuizMode.mock, 0, false, 45),
      ('----', QuizMode.mock, 0, false, 25),
      ('cw', QuizMode.revision, 3, true, 12),
      ('cw', QuizMode.currentAffairs, 3, true, 12),
    ];
    for (final (p, mode, streak, counts, want) in cases) {
      test('$p ${mode.name} streak $streak counts $counts -> $want', () {
        expect(xpFor(result(p, mode: mode), streak: streak, countsForStreak: counts), want);
      });
    }
  });

  group('LevelInfo', () {
    final starts = {1: 0, 2: 100, 3: 300, 4: 600, 5: 1000, 6: 1500, 10: 4500};
    starts.forEach((l, xp) {
      test('level $l starts at $xp', () {
        expect(LevelInfo.startOf(l), xp);
        expect(LevelInfo.fromXp(xp).level, l);
        expect(LevelInfo.fromXp(xp).xpIntoLevel, 0);
        if (xp > 0) expect(LevelInfo.fromXp(xp - 1).level, l - 1);
      });
    });
    test('progress inside a level', () {
      final i = LevelInfo.fromXp(150);
      expect(i.level, 2);
      expect(i.xpIntoLevel, 50);
      expect(i.xpForNext, 200);
      expect(i.progress, 0.25);
    });
    test('negative xp is level 1', () {
      final i = LevelInfo.fromXp(-50);
      expect(i.level, 1);
      expect(i.xpIntoLevel, 0);
    });
    test('progress is between 0 and 1 for many xp values', () {
      for (var xp = 0; xp < 20000; xp += 37) {
        final i = LevelInfo.fromXp(xp);
        expect(i.progress, inInclusiveRange(0, 1));
        expect(LevelInfo.startOf(i.level) + i.xpIntoLevel, xp);
      }
    });
  });

  group('Achievement', () {
    Progress p({StatsBook? stats, int best = 0, int xp = 0}) =>
        Progress(stats: stats ?? StatsBook(), bestStreak: best, xp: xp);

    test('nothing earned at the start', () => expect(Achievement.earnedBy(p()), isEmpty));
    test('first quiz', () {
      expect(Achievement.firstQuiz.earned(p(stats: StatsBook()..quizzes = 1)), isTrue);
    });
    for (final (a, need) in [
      (Achievement.streak3, 3),
      (Achievement.streak7, 7),
      (Achievement.streak30, 30)
    ]) {
      test('${a.name} needs a best streak of $need', () {
        expect(a.earned(p(best: need - 1)), isFalse);
        expect(a.earned(p(best: need)), isTrue);
      });
    }
    for (final (a, need) in [
      (Achievement.answered100, 100),
      (Achievement.answered500, 500),
      (Achievement.answered1000, 1000)
    ]) {
      test('${a.name} needs $need answers', () {
        expect(a.earned(p(stats: StatsBook()..bySubject['gk'] = Tally(need - 1, 0))), isFalse);
        expect(a.earned(p(stats: StatsBook()..bySubject['gk'] = Tally(need, 0))), isTrue);
      });
    }
    test('perfect daily', () {
      expect(Achievement.perfectDaily.earned(p(stats: StatsBook()..perfectDailies = 1)), isTrue);
    });
    test('first mock', () {
      expect(Achievement.firstMock.earned(p(stats: StatsBook()..mocks = 1)), isTrue);
    });
    test('all-rounder needs 5 subjects with 10 answers', () {
      final b = StatsBook();
      for (final s in ['gk', 'history', 'polity', 'maths']) {
        b.bySubject[s] = Tally(10, 1);
      }
      expect(Achievement.allRounder.earned(p(stats: b)), isFalse);
      b.bySubject['english'] = Tally(9, 1);
      expect(Achievement.allRounder.earned(p(stats: b)), isFalse);
      b.bySubject['english'] = Tally(10, 1);
      expect(Achievement.allRounder.earned(p(stats: b)), isTrue);
    });
    test('CA reader needs 7 days read', () {
      final b = StatsBook()..caDaysRead.addAll([for (var i = 0; i < 6; i++) today.addDays(-i).key]);
      expect(Achievement.caReader.earned(p(stats: b)), isFalse);
      b.caDaysRead.add(today.addDays(-6).key);
      expect(Achievement.caReader.earned(p(stats: b)), isTrue);
    });
    test('sharp shooter: 100 answers at 80%', () {
      expect(Achievement.sharpShooter.earned(p(stats: StatsBook()..bySubject['gk'] = Tally(100, 79))),
          isFalse);
      expect(Achievement.sharpShooter.earned(p(stats: StatsBook()..bySubject['gk'] = Tally(100, 80))),
          isTrue);
      expect(Achievement.sharpShooter.earned(p(stats: StatsBook()..bySubject['gk'] = Tally(99, 99))),
          isFalse);
    });
    test('level badges', () {
      expect(Achievement.level5.earned(p(xp: 999)), isFalse);
      expect(Achievement.level5.earned(p(xp: 1000)), isTrue);
      expect(Achievement.level10.earned(p(xp: 4499)), isFalse);
      expect(Achievement.level10.earned(p(xp: 4500)), isTrue);
    });
    for (final a in Achievement.values) {
      test('parse ${a.name}', () => expect(Achievement.parse(a.name), a));
    }
    test('parse unknown', () {
      expect(Achievement.parse('nope'), isNull);
      expect(Achievement.parse(null), isNull);
      expect(Achievement.parse(3), isNull);
    });
    test('everything earned by a veteran', () {
      final b = StatsBook()
        ..quizzes = 100
        ..mocks = 3
        ..perfectDailies = 5;
      for (final s in ['gk', 'history', 'polity', 'maths', 'english']) {
        b.bySubject[s] = Tally(300, 270);
      }
      b.caDaysRead.addAll([for (var i = 0; i < 10; i++) today.addDays(-i).key]);
      expect(Achievement.earnedBy(p(stats: b, best: 40, xp: 99999)), Achievement.values.toSet());
    });
  });
}
