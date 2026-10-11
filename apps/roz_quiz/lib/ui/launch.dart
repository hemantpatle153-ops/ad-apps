import 'package:flutter/material.dart';

import '../core/day.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../data/user_store.dart';
import 'quiz_screen.dart';
import 'review_screen.dart';
import 'scope.dart';

/// Opens an instant-feedback quiz with the user's timer setting.
Future<void> openQuiz(
  BuildContext context, {
  required QuizMode mode,
  required List<Question> questions,
  required String title,
  Day? dailyDate,
}) {
  if (questions.isEmpty) return Future.value();
  final secs = AppScope.read(context).settings.timerSeconds;
  final session = QuizSession(
    mode: mode,
    questions: questions,
    perQuestionLimit: secs > 0 ? Duration(seconds: secs) : null,
  );
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => QuizScreen(session: session, title: title, dailyDate: dailyDate),
  ));
}

/// Review of a Daily Quiz played earlier, rebuilt from its saved choices.
Future<void> openDailyReview(
    BuildContext context, List<Question> questions, DailyRecord record) {
  final choices = [
    for (var i = 0; i < questions.length; i++)
      i < record.choices.length ? record.choices[i] : null
  ];
  final result = QuizResult.score(
    mode: QuizMode.daily,
    questions: questions,
    choices: choices,
    timesMs: List.filled(questions.length, 0),
    durationMs: record.timeMs,
  );
  return Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ReviewScreen(result: result)));
}
