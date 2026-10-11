import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/core/session.dart';

import 'support/harness.dart';

List<Question> qs(int n, {List<String>? subjects}) => [
      for (var i = 0; i < n; i++)
        makeQ(
          id: 'q$i',
          answer: i % 4,
          subject: subjects == null ? 'gk' : subjects[i % subjects.length],
        )
    ];

const sec = Duration(seconds: 1);

void main() {
  group('NegativeMarking', () {
    test('values', () {
      expect(NegativeMarking.none.value, 0);
      expect(NegativeMarking.quarter.value, 0.25);
      expect(NegativeMarking.third.value, closeTo(0.3333, 1e-4));
      expect(NegativeMarking.half.value, 0.5);
    });
    test('labels', () {
      expect(NegativeMarking.none.label, '0');
      expect(NegativeMarking.quarter.label, '1/4');
      expect(NegativeMarking.third.label, '1/3');
      expect(NegativeMarking.half.label, '1/2');
    });
    for (final n in NegativeMarking.values) {
      test('parse round-trips ${n.name}', () => expect(NegativeMarking.parse(n.name), n));
    }
    for (final bad in [null, '', 'QUARTER', 3, '1/4']) {
      test('parse "$bad" falls back to none', () => expect(NegativeMarking.parse(bad), NegativeMarking.none));
    }
  });

  group('QuizSession construction', () {
    test('rejects an empty quiz', () {
      expect(() => QuizSession(mode: QuizMode.daily, questions: const []), throwsArgumentError);
    });
    test('rejects zero or negative marks', () {
      expect(() => QuizSession(mode: QuizMode.mock, questions: qs(2), marksPerQuestion: 0),
          throwsArgumentError);
      expect(() => QuizSession(mode: QuizMode.mock, questions: qs(2), marksPerQuestion: -1),
          throwsArgumentError);
    });
    test('starts at the first question, which is visited', () {
      final s = QuizSession(mode: QuizMode.daily, questions: qs(3));
      expect(s.current, 0);
      expect(s.isFirst, isTrue);
      expect(s.isLast, isFalse);
      expect(s.states[0].visited, isTrue);
      expect(s.states[1].visited, isFalse);
      expect(s.submitted, isFalse);
      expect(s.result, isNull);
      expect(s.length, 3);
    });
    test('the question list cannot be changed from outside', () {
      final s = QuizSession(mode: QuizMode.daily, questions: qs(2));
      expect(() => s.questions.add(makeQ()), throwsUnsupportedError);
    });
    test('changing the source list later does not change the quiz', () {
      final list = qs(2);
      final s = QuizSession(mode: QuizMode.daily, questions: list);
      list.clear();
      expect(s.length, 2);
    });
    for (final m in QuizMode.values) {
      test('instant feedback for ${m.name}: ${m != QuizMode.mock}', () {
        expect(QuizSession(mode: m, questions: qs(1)).instantFeedback, m != QuizMode.mock);
      });
    }
  });

  group('instant-feedback answering', () {
    late QuizSession s;
    setUp(() => s = QuizSession(mode: QuizMode.daily, questions: qs(4)));

    test('first choice is accepted', () {
      expect(s.answer(2), isTrue);
      expect(s.state.selected, 2);
      expect(s.answeredCount, 1);
    });
    test('a second choice is refused (the first is final)', () {
      s.answer(2);
      expect(s.answer(1), isFalse);
      expect(s.state.selected, 2);
    });
    for (final bad in [-1, 4, 99]) {
      test('choice $bad is out of range', () {
        expect(s.answer(bad), isFalse);
        expect(s.state.answered, isFalse);
      });
    }
    test('answered question is closed', () {
      expect(s.isClosed(0), isFalse);
      s.answer(0);
      expect(s.isClosed(0), isTrue);
    });
    test('clear and mark are mock-only', () {
      s.answer(0);
      expect(s.clear(), isFalse);
      expect(s.state.selected, 0);
      expect(s.toggleMark(), isFalse);
      expect(s.state.marked, isFalse);
    });
    test('allClosed after every question is answered', () {
      for (var i = 0; i < 4; i++) {
        expect(s.allClosed, isFalse);
        s.goTo(i);
        s.answer(0);
      }
      expect(s.allClosed, isTrue);
    });
    test('cannot answer after submit', () {
      s.submit();
      s.goTo(1);
      expect(s.answer(1), isFalse);
    });
  });

  group('navigation', () {
    late QuizSession s;
    setUp(() => s = QuizSession(mode: QuizMode.mock, questions: qs(3)));

    test('next walks forward and stops at the end', () {
      expect(s.next(), isTrue);
      expect(s.current, 1);
      expect(s.next(), isTrue);
      expect(s.isLast, isTrue);
      expect(s.next(), isFalse);
      expect(s.current, 2);
    });
    test('previous walks back and stops at the start', () {
      expect(s.previous(), isFalse);
      s.goTo(2);
      expect(s.previous(), isTrue);
      expect(s.current, 1);
    });
    test('goTo marks visited', () {
      s.goTo(2);
      expect(s.states[2].visited, isTrue);
      expect(s.states[1].visited, isFalse);
    });
    for (final bad in [-1, 3, 100]) {
      test('goTo($bad) is ignored', () {
        s.goTo(bad);
        expect(s.current, 0);
      });
    }
    test('goTo is ignored after submit', () {
      s.submit();
      s.goTo(2);
      expect(s.current, 0);
    });
    test('question and state follow current', () {
      s.goTo(1);
      expect(s.question.id, 'q1');
      expect(identical(s.state, s.states[1]), isTrue);
    });
  });

  group('mock answering', () {
    late QuizSession s;
    setUp(() => s = QuizSession(mode: QuizMode.mock, questions: qs(4)));

    test('answers can be changed', () {
      s.answer(1);
      expect(s.answer(3), isTrue);
      expect(s.state.selected, 3);
    });
    test('clear removes the answer', () {
      s.answer(1);
      expect(s.clear(), isTrue);
      expect(s.state.answered, isFalse);
    });
    test('clear without an answer does nothing', () => expect(s.clear(), isFalse));
    test('toggleMark flips', () {
      expect(s.toggleMark(), isTrue);
      expect(s.state.marked, isTrue);
      expect(s.toggleMark(), isTrue);
      expect(s.state.marked, isFalse);
    });
    test('questions are never closed before submit', () {
      s.answer(0);
      expect(s.isClosed(0), isFalse);
      s.submit();
      expect(s.isClosed(0), isTrue);
      expect(s.isClosed(3), isTrue);
    });
    test('nothing changes after submit', () {
      s.answer(1);
      s.submit();
      expect(s.answer(2), isFalse);
      expect(s.clear(), isFalse);
      expect(s.toggleMark(), isFalse);
      expect(s.state.selected, 1);
    });
  });

  group('palette', () {
    late QuizSession s;
    setUp(() => s = QuizSession(mode: QuizMode.mock, questions: qs(5)));

    test('initial statuses', () {
      expect(s.status(0), PaletteStatus.notAnswered);
      for (var i = 1; i < 5; i++) {
        expect(s.status(i), PaletteStatus.notVisited);
      }
    });
    test('answered', () {
      s.answer(0);
      expect(s.status(0), PaletteStatus.answered);
    });
    test('marked without answer', () {
      s.toggleMark();
      expect(s.status(0), PaletteStatus.marked);
    });
    test('answered and marked', () {
      s.answer(0);
      s.toggleMark();
      expect(s.status(0), PaletteStatus.answeredMarked);
    });
    test('clearing a marked answer leaves it marked', () {
      s.answer(0);
      s.toggleMark();
      s.clear();
      expect(s.status(0), PaletteStatus.marked);
    });
    test('visited without answer', () {
      s.goTo(3);
      expect(s.status(3), PaletteStatus.notAnswered);
    });
    test('counts cover every question', () {
      s.answer(0);
      s.goTo(1);
      s.toggleMark();
      s.goTo(2);
      s.answer(1);
      s.toggleMark();
      s.goTo(3);
      final c = s.paletteCounts();
      expect(c[PaletteStatus.answered], 1);
      expect(c[PaletteStatus.marked], 1);
      expect(c[PaletteStatus.answeredMarked], 1);
      expect(c[PaletteStatus.notAnswered], 1);
      expect(c[PaletteStatus.notVisited], 1);
      expect(c.values.reduce((a, b) => a + b), 5);
    });
    test('counts have every status key even when zero', () {
      expect(s.paletteCounts().keys.toSet(), PaletteStatus.values.toSet());
    });
  });

  group('per-question timer', () {
    QuizSession timed([int seconds = 30]) => QuizSession(
        mode: QuizMode.practice, questions: qs(3), perQuestionLimit: Duration(seconds: seconds));

    test('no timer means no time left value', () {
      expect(QuizSession(mode: QuizMode.daily, questions: qs(1)).questionTimeLeft, isNull);
    });
    test('mock ignores perQuestionLimit', () {
      final s = QuizSession(mode: QuizMode.mock, questions: qs(1), perQuestionLimit: sec);
      expect(s.questionTimeLeft, isNull);
    });
    test('counts down', () {
      final s = timed();
      expect(s.questionTimeLeft, const Duration(seconds: 30));
      s.tick(sec);
      expect(s.questionTimeLeft, const Duration(seconds: 29));
    });
    test('times out at the limit', () {
      final s = timed(3);
      expect(s.tick(sec), TickEvent.none);
      expect(s.tick(sec), TickEvent.none);
      expect(s.tick(sec), TickEvent.questionTimedOut);
      expect(s.state.timedOut, isTrue);
      expect(s.isClosed(0), isTrue);
      expect(s.questionTimeLeft, Duration.zero);
    });
    test('a big tick clamps time spent to the limit', () {
      final s = timed(3);
      expect(s.tick(const Duration(seconds: 10)), TickEvent.questionTimedOut);
      expect(s.state.timeMs, 3000);
    });
    test('timed-out question cannot be answered', () {
      final s = timed(1);
      s.tick(sec);
      expect(s.answer(0), isFalse);
    });
    test('the timer stops once answered', () {
      final s = timed(5);
      s.tick(sec);
      s.answer(0);
      expect(s.tick(const Duration(seconds: 10)), TickEvent.none);
      expect(s.state.timeMs, 1000);
      expect(s.state.timedOut, isFalse);
    });
    test('each question has its own clock', () {
      final s = timed(5);
      s.tick(const Duration(seconds: 2));
      s.answer(0);
      s.next();
      expect(s.questionTimeLeft, const Duration(seconds: 5));
      s.tick(sec);
      expect(s.states[1].timeMs, 1000);
      expect(s.states[0].timeMs, 2000);
    });
    test('timed-out questions count as closed for allClosed', () {
      final s = timed(1);
      s.tick(sec);
      s.next();
      s.answer(1);
      s.next();
      s.tick(sec);
      expect(s.allClosed, isTrue);
    });
    test('elapsed adds up across questions', () {
      final s = timed(5);
      s.tick(sec);
      s.answer(0);
      s.tick(sec);
      expect(s.elapsed, const Duration(seconds: 2));
    });
    test('negative ticks are ignored', () {
      final s = timed(5);
      expect(s.tick(const Duration(seconds: -3)), TickEvent.none);
      expect(s.elapsed, Duration.zero);
    });
    test('no ticks after submit', () {
      final s = timed(5);
      s.submit();
      expect(s.tick(sec), TickEvent.none);
      expect(s.elapsed, Duration.zero);
    });
  });

  group('mock total timer', () {
    QuizSession mock([int seconds = 10]) => QuizSession(
        mode: QuizMode.mock, questions: qs(3), totalLimit: Duration(seconds: seconds));

    test('untimed when no limit', () {
      expect(QuizSession(mode: QuizMode.mock, questions: qs(1)).totalTimeLeft, isNull);
    });
    test('counts down', () {
      final s = mock();
      s.tick(sec);
      expect(s.totalTimeLeft, const Duration(seconds: 9));
    });
    test('time on each question is tracked', () {
      final s = mock();
      s.tick(sec);
      s.goTo(2);
      s.tick(sec);
      s.tick(sec);
      expect(s.states[0].timeMs, 1000);
      expect(s.states[2].timeMs, 2000);
    });
    test('submits when time is up', () {
      final s = mock(2);
      s.answer(s.question.answer);
      expect(s.tick(sec), TickEvent.none);
      expect(s.tick(sec), TickEvent.timeUp);
      expect(s.submitted, isTrue);
      expect(s.result!.correct, 1);
      expect(s.totalTimeLeft, Duration.zero);
    });
    test('overshoot is clamped', () {
      final s = mock(2);
      s.tick(const Duration(seconds: 7));
      expect(s.result!.durationMs, 2000);
    });
    test('answers stay changeable while time remains', () {
      final s = mock(10);
      s.tick(const Duration(seconds: 9));
      expect(s.answer(1), isTrue);
      expect(s.answer(2), isTrue);
    });
  });

  group('submit', () {
    test('returns the same result twice', () {
      final s = QuizSession(mode: QuizMode.daily, questions: qs(2));
      s.answer(0);
      final r1 = s.submit();
      final r2 = s.submit();
      expect(identical(r1, r2), isTrue);
      expect(s.result, same(r1));
    });
    test('result carries mode, choices and times', () {
      final s = QuizSession(
          mode: QuizMode.practice, questions: qs(2), perQuestionLimit: const Duration(seconds: 9));
      s.tick(const Duration(seconds: 2));
      s.answer(0);
      s.next();
      s.tick(sec);
      final r = s.submit();
      expect(r.mode, QuizMode.practice);
      expect(r.choices, [0, null]);
      expect(r.timesMs, [2000, 1000]);
      expect(r.durationMs, 3000);
    });
  });

  group('scoring table', () {
    // (answers given: c = correct, w = wrong, - = blank), marking, marks,
    // expected score.
    final cases = <(String, NegativeMarking, double, double)>[
      ('cccc', NegativeMarking.none, 1, 4),
      ('cccc', NegativeMarking.quarter, 1, 4),
      ('wwww', NegativeMarking.none, 1, 0),
      ('wwww', NegativeMarking.quarter, 1, -1),
      ('wwww', NegativeMarking.half, 1, -2),
      ('wwww', NegativeMarking.third, 3, -4),
      ('----', NegativeMarking.half, 1, 0),
      ('ccww', NegativeMarking.quarter, 1, 1.5),
      ('ccww', NegativeMarking.quarter, 2, 3),
      ('ccww', NegativeMarking.third, 1, 2 - 2 / 3),
      ('cw--', NegativeMarking.half, 1, 0.5),
      ('cw--', NegativeMarking.half, 2, 1),
      ('cccw', NegativeMarking.quarter, 2, 5.5),
      ('c---', NegativeMarking.quarter, 1, 1),
      ('-w-w', NegativeMarking.quarter, 4, -2),
      ('ccc-', NegativeMarking.third, 1, 3),
      ('cwcw', NegativeMarking.none, 2, 4),
      ('wwwc', NegativeMarking.third, 3, 0),
    ];
    for (final (pattern, neg, marks, want) in cases) {
      test('$pattern with ${neg.label} and $marks marks scores $want', () {
        final list = qs(4);
        final choices = [
          for (var i = 0; i < 4; i++)
            switch (pattern[i]) {
              'c' => list[i].answer,
              'w' => (list[i].answer + 1) % 4,
              _ => null,
            }
        ];
        final r = QuizResult.score(
            mode: QuizMode.mock,
            questions: list,
            choices: choices,
            timesMs: List.filled(4, 0),
            negative: neg,
            marksPerQuestion: marks);
        expect(r.score, closeTo(want, 1e-9));
        expect(r.maxScore, 4 * marks);
        final c = 'c'.allMatches(pattern).length;
        final w = 'w'.allMatches(pattern).length;
        expect(r.correct, c);
        expect(r.wrong, w);
        expect(r.unanswered, 4 - c - w);
        expect(r.attempted, c + w);
        expect(r.accuracy, c + w == 0 ? 0 : c / (c + w));
        expect(r.percent, closeTo(want / (4 * marks), 1e-9));
        expect(r.perfect, c == 4);
        expect(r.wrongQuestions.length, w);
        expect(r.correctQuestions.length, c);
      });
    }
    test('mismatched lengths throw', () {
      expect(
          () => QuizResult.score(
              mode: QuizMode.daily, questions: qs(2), choices: [0], timesMs: [0, 0]),
          throwsArgumentError);
      expect(
          () => QuizResult.score(
              mode: QuizMode.daily, questions: qs(2), choices: [0, 1], timesMs: [0]),
          throwsArgumentError);
    });
    test('choices list is read-only', () {
      final r = QuizResult.score(
          mode: QuizMode.daily, questions: qs(1), choices: [0], timesMs: [0]);
      expect(() => r.choices[0] = 1, throwsUnsupportedError);
    });
  });

  group('sections', () {
    test('grouped by subject with their own scores', () {
      final list = qs(6, subjects: ['polity', 'maths', 'science']);
      // q0 polity c, q1 maths w, q2 science -, q3 polity w, q4 maths c, q5 science c
      final choices = <int?>[
        list[0].answer,
        (list[1].answer + 1) % 4,
        null,
        (list[3].answer + 1) % 4,
        list[4].answer,
        list[5].answer,
      ];
      final r = QuizResult.score(
          mode: QuizMode.mock,
          questions: list,
          choices: choices,
          timesMs: [1, 2, 3, 4, 5, 6],
          negative: NegativeMarking.quarter,
          marksPerQuestion: 2);
      final by = {for (final s in r.sections) s.subject: s};
      expect(by.keys, ['polity', 'maths', 'science']);
      expect(by['polity']!.correct, 1);
      expect(by['polity']!.wrong, 1);
      expect(by['polity']!.score, 1.5);
      expect(by['polity']!.timeMs, 5);
      expect(by['maths']!.score, 1.5);
      expect(by['science']!.unanswered, 1);
      expect(by['science']!.score, 2);
      expect(by['science']!.accuracy, 1);
      expect(by['science']!.attempted, 1);
      final sum = r.sections.fold<double>(0, (a, s) => a + s.score);
      expect(sum, closeTo(r.score, 1e-9));
    });
    test('a section with nothing attempted has zero accuracy', () {
      final s = SectionResult('gk')..total = 3;
      expect(s.accuracy, 0);
      expect(s.unanswered, 3);
    });
  });

  group('formatScore', () {
    final cases = {
      0.0: '0',
      7.0: '7',
      6.75: '6.75',
      6.5: '6.5',
      2 / 3: '0.67',
      -1.5: '-1.5',
      -0.25: '-0.25',
      100.0: '100',
      1.006: '1.01',
      -0.001: '0',
      12.333333: '12.33',
      0.1: '0.1',
    };
    cases.forEach((v, s) => test('$v -> $s', () => expect(formatScore(v), s)));
  });

  group('formatClock', () {
    final cases = {
      Duration.zero: '0:00',
      const Duration(seconds: 5): '0:05',
      const Duration(seconds: 59): '0:59',
      const Duration(minutes: 1): '1:00',
      const Duration(minutes: 9, seconds: 9): '9:09',
      const Duration(minutes: 60): '1:00:00',
      const Duration(hours: 1, minutes: 5, seconds: 7): '1:05:07',
      const Duration(seconds: -4): '0:00',
      const Duration(milliseconds: 1999): '0:01',
    };
    cases.forEach((d, s) => test('$d -> $s', () => expect(formatClock(d), s)));
  });
}
