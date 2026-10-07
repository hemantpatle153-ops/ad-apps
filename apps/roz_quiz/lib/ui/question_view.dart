import 'package:flutter/material.dart';

import '../core/bi.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Subject, difficulty and "Asked in" tags above a question.
class QuestionTags extends StatelessWidget {
  const QuestionTags({super.key, required this.question});
  final Question question;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final q = question;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      Tag(s.subject(q.subject),
          icon: subjectIcon(q.subject), color: subjectColor(q.subject)),
      Tag(s.difficulty(q.difficulty), color: context.colors.secondary),
      if (q.asked != null)
        Tag(s.f(T.askedIn, {'exam': q.asked!}),
            icon: Icons.history_edu, color: context.quiz.marked),
    ]);
  }
}

/// The question text in a card.
class QuestionText extends StatelessWidget {
  const QuestionText({super.key, required this.question, required this.lang});
  final Question question;
  final Lang lang;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(
          question.q.of(lang),
          style: context.text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700, height: 1.35, fontSize: 21),
        ),
      );
}

/// Shown under the options after answering: verdict, right answer,
/// explanation and source.
class AnswerExplanation extends StatelessWidget {
  const AnswerExplanation({
    super.key,
    required this.question,
    required this.choice,
    required this.lang,
    this.timedOut = false,
    this.onOpenSource,
  });

  final Question question;
  final int? choice;
  final Lang lang;
  final bool timedOut;
  final void Function(String url)? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final q = context.quiz;
    final right = question.isCorrect(choice);
    final (icon, title, color) = timedOut && choice == null
        ? (Icons.timer_off, s.t(T.timeUp), q.wrong)
        : choice == null
            ? (Icons.skip_next, s.t(T.skipped), context.colors.onSurfaceVariant)
            : right
                ? (Icons.check_circle, s.t(T.correct), q.correct)
                : (Icons.cancel, s.t(T.wrong), q.wrong);
    final exp = question.explanation.of(lang);
    final src = question.source;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (right ? q.correctSoft : context.colors.surfaceContainer),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: context.text.titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w800)),
              ),
            ]),
            if (!right) ...[
              const SizedBox(height: 8),
              Text(
                s.f(T.correctAnswerIs, {
                  'answer':
                      '${OptionButton.letters[question.answer]}. ${question.options[question.answer].of(lang)}'
                }),
                style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
            if (exp.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(s.t(T.explanation),
                  style: context.text.labelLarge
                      ?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(exp, style: context.text.bodyLarge?.copyWith(height: 1.4)),
            ],
            if (src != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: src.url == null || onOpenSource == null
                    ? null
                    : () => onOpenSource!(src.url!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.link, size: 16, color: context.colors.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(s.f(T.sourceLabel, {'name': src.name}),
                          style: context.text.bodySmall
                              ?.copyWith(color: context.colors.primary)),
                    ),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Semantics label for an option.
String optionSemantics(S s, int i, String text) =>
    s.f(T.optionLabel, {'letter': OptionButton.letters[i], 'text': text});
