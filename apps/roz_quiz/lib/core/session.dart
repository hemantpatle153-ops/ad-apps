import 'models.dart';

enum QuizMode { daily, practice, currentAffairs, mock, revision }

/// Marks taken off for each wrong answer, as a fraction of one question's
/// marks. Unanswered questions never lose marks.
enum NegativeMarking {
  none(0, 0, 1),
  quarter(0.25, 1, 4),
  third(1 / 3, 1, 3),
  half(0.5, 1, 2);

  const NegativeMarking(this.value, this.numerator, this.denominator);
  final double value;
  final int numerator;
  final int denominator;

  String get label => this == none ? '0' : '$numerator/$denominator';

  static NegativeMarking parse(Object? v) => NegativeMarking.values
      .firstWhere((n) => n.name == v, orElse: () => NegativeMarking.none);
}

/// The colour of a question in the mock test palette.
enum PaletteStatus { notVisited, notAnswered, answered, marked, answeredMarked }

/// What happened on a [QuizSession.tick].
enum TickEvent { none, questionTimedOut, timeUp }

class QuestionState {
  int? selected;
  bool marked = false;
  bool visited = false;
  bool timedOut = false;

  /// Time spent on the question, until it was answered (instant feedback)
  /// or in total (mock test).
  int timeMs = 0;

  bool get answered => selected != null;
}

/// The rules of one quiz run: answering, navigation, timers, palette and
/// scoring. Pure Dart; the screens drive it and call [tick] once a second.
///
/// Two styles:
/// * instant feedback (daily, practice, current affairs, revision): the
///   first choice is final and the answer is shown at once; an optional
///   per-question timer ends a question unanswered.
/// * mock test: answers can be changed or cleared and marked for review
///   until submit; nothing is revealed before; one timer for the whole test
///   submits automatically when it runs out.
class QuizSession {
  QuizSession({
    required this.mode,
    required List<Question> questions,
    this.perQuestionLimit,
    this.totalLimit,
    this.negative = NegativeMarking.none,
    this.marksPerQuestion = 1,
  })  : questions = List.unmodifiable(questions),
        states = [for (var i = 0; i < questions.length; i++) QuestionState()] {
    if (questions.isEmpty) throw ArgumentError('A quiz needs questions');
    if (marksPerQuestion <= 0) throw ArgumentError('marksPerQuestion <= 0');
    states.first.visited = true;
  }

  final QuizMode mode;
  final List<Question> questions;
  final List<QuestionState> states;

  /// Instant-feedback modes only; null = no timer.
  final Duration? perQuestionLimit;

  /// Mock tests only; null = untimed.
  final Duration? totalLimit;
  final NegativeMarking negative;
  final double marksPerQuestion;

  int _current = 0;
  int _elapsedMs = 0;
  QuizResult? _result;

  bool get instantFeedback => mode != QuizMode.mock;
  int get current => _current;
  int get length => questions.length;
  Question get question => questions[_current];
  QuestionState get state => states[_current];
  bool get isFirst => _current == 0;
  bool get isLast => _current == questions.length - 1;
  bool get submitted => _result != null;
  QuizResult? get result => _result;
  Duration get elapsed => Duration(milliseconds: _elapsedMs);

  /// A question is closed once it can no longer be answered.
  bool isClosed(int i) =>
      submitted ||
      (instantFeedback && (states[i].answered || states[i].timedOut));

  Duration? get questionTimeLeft {
    final limit = perQuestionLimit;
    if (limit == null || !instantFeedback) return null;
    final left = limit.inMilliseconds - state.timeMs;
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  Duration? get totalTimeLeft {
    final limit = totalLimit;
    if (limit == null) return null;
    final left = limit.inMilliseconds - _elapsedMs;
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  /// Number of questions answered so far.
  int get answeredCount => states.where((s) => s.answered).length;

  /// Every question is answered or timed out (instant feedback), so the
  /// quiz can finish.
  bool get allClosed =>
      List.generate(length, isClosed).every((closed) => closed);

  void goTo(int i) {
    if (submitted || i < 0 || i >= questions.length) return;
    _current = i;
    states[i].visited = true;
  }

  /// Moves on; false at the last question.
  bool next() {
    if (isLast) return false;
    goTo(_current + 1);
    return true;
  }

  bool previous() {
    if (isFirst) return false;
    goTo(_current - 1);
    return true;
  }

  /// Chooses [choice] for the current question. Returns false when the
  /// choice is not allowed (closed question, out of range, submitted).
  bool answer(int choice) {
    if (choice < 0 || choice > 3 || isClosed(_current)) return false;
    state.selected = choice;
    return true;
  }

  /// Mock tests: removes the answer of the current question.
  bool clear() {
    if (instantFeedback || submitted || !state.answered) return false;
    state.selected = null;
    return true;
  }

  /// Mock tests: flags the current question to come back to.
  bool toggleMark() {
    if (instantFeedback || submitted) return false;
    state.marked = !state.marked;
    return true;
  }

  /// Adds [d] of elapsed time. Call about once a second while the quiz
  /// screen is visible (not while paused in the background).
  TickEvent tick(Duration d) {
    if (submitted || d.isNegative) return TickEvent.none;
    final ms = d.inMilliseconds;
    _elapsedMs += ms;
    if (instantFeedback) {
      if (!isClosed(_current)) {
        state.timeMs += ms;
        final limit = perQuestionLimit;
        if (limit != null && state.timeMs >= limit.inMilliseconds) {
          state.timeMs = limit.inMilliseconds;
          state.timedOut = true;
          return TickEvent.questionTimedOut;
        }
      }
      return TickEvent.none;
    }
    state.timeMs += ms;
    final limit = totalLimit;
    if (limit != null && _elapsedMs >= limit.inMilliseconds) {
      _elapsedMs = limit.inMilliseconds;
      submit();
      return TickEvent.timeUp;
    }
    return TickEvent.none;
  }

  PaletteStatus status(int i) {
    final s = states[i];
    if (!s.visited) return PaletteStatus.notVisited;
    if (s.marked) {
      return s.answered ? PaletteStatus.answeredMarked : PaletteStatus.marked;
    }
    return s.answered ? PaletteStatus.answered : PaletteStatus.notAnswered;
  }

  Map<PaletteStatus, int> paletteCounts() {
    final counts = {for (final p in PaletteStatus.values) p: 0};
    for (var i = 0; i < length; i++) {
      counts[status(i)] = counts[status(i)]! + 1;
    }
    return counts;
  }

  /// Ends the quiz and scores it. Calling again returns the same result.
  QuizResult submit() => _result ??= QuizResult.score(
        mode: mode,
        questions: questions,
        choices: [for (final s in states) s.selected],
        timesMs: [for (final s in states) s.timeMs],
        negative: negative,
        marksPerQuestion: marksPerQuestion,
        durationMs: _elapsedMs,
      );
}

/// Score of one subject (a mock test section).
class SectionResult {
  SectionResult(this.subject);
  final String subject;
  int total = 0;
  int correct = 0;
  int wrong = 0;
  int timeMs = 0;
  double score = 0;

  int get unanswered => total - correct - wrong;
  int get attempted => correct + wrong;
  double get accuracy => attempted == 0 ? 0 : correct / attempted;
}

class QuizResult {
  const QuizResult({
    required this.mode,
    required this.questions,
    required this.choices,
    required this.timesMs,
    required this.correct,
    required this.wrong,
    required this.score,
    required this.maxScore,
    required this.durationMs,
    required this.negative,
    required this.sections,
  });

  /// Scores [choices] (null = not answered) against [questions].
  factory QuizResult.score({
    required QuizMode mode,
    required List<Question> questions,
    required List<int?> choices,
    required List<int> timesMs,
    NegativeMarking negative = NegativeMarking.none,
    double marksPerQuestion = 1,
    int durationMs = 0,
  }) {
    if (choices.length != questions.length ||
        timesMs.length != questions.length) {
      throw ArgumentError('choices and times must match questions');
    }
    var correct = 0, wrong = 0;
    final sections = <String, SectionResult>{};
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final c = choices[i];
      final sec = sections.putIfAbsent(q.subject, () => SectionResult(q.subject));
      sec.total++;
      sec.timeMs += timesMs[i];
      if (c == null) continue;
      if (q.isCorrect(c)) {
        correct++;
        sec.correct++;
        sec.score += marksPerQuestion;
      } else {
        wrong++;
        sec.wrong++;
        sec.score -= marksPerQuestion * negative.value;
      }
    }
    return QuizResult(
      mode: mode,
      questions: questions,
      choices: List.unmodifiable(choices),
      timesMs: List.unmodifiable(timesMs),
      correct: correct,
      wrong: wrong,
      score: correct * marksPerQuestion -
          wrong * marksPerQuestion * negative.value,
      maxScore: questions.length * marksPerQuestion,
      durationMs: durationMs,
      negative: negative,
      sections: sections.values.toList(),
    );
  }

  final QuizMode mode;
  final List<Question> questions;
  final List<int?> choices;
  final List<int> timesMs;
  final int correct;
  final int wrong;
  final double score;
  final double maxScore;
  final int durationMs;
  final NegativeMarking negative;
  final List<SectionResult> sections;

  int get total => questions.length;
  int get unanswered => total - correct - wrong;
  int get attempted => correct + wrong;

  /// Correct answers out of attempted ones (0 when nothing attempted).
  double get accuracy => attempted == 0 ? 0 : correct / attempted;

  /// Score out of the maximum, can be negative with negative marking.
  double get percent => maxScore == 0 ? 0 : score / maxScore;

  bool get perfect => correct == total;

  /// Questions answered wrongly, for "My mistakes".
  List<Question> get wrongQuestions => [
        for (var i = 0; i < total; i++)
          if (choices[i] != null && !questions[i].isCorrect(choices[i]))
            questions[i]
      ];

  List<Question> get correctQuestions => [
        for (var i = 0; i < total; i++)
          if (questions[i].isCorrect(choices[i])) questions[i]
      ];
}

/// Formats a score with up to two decimals: 7, 6.75, 6.67, -1.5.
String formatScore(double v) {
  final r = (v * 100).round() / 100;
  if (r == r.roundToDouble()) return r.toInt().toString();
  var s = r.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s == '-0' ? '0' : s;
}

/// m:ss or h:mm:ss.
String formatClock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
