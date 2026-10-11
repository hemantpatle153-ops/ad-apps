import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../core/bi.dart';
import '../core/session.dart';
import '../l10n/strings.dart';
import 'question_view.dart';
import 'report_sheet.dart';
import 'scope.dart';
import 'widgets.dart';

/// Every question of a finished quiz with the user's answer, the right
/// answer and the explanation.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.result});
  final QuizResult result;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _other = false;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final lang = _other ? app.lang.other : app.lang;
    final r = widget.result;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(T.reviewTitle)),
        actions: [
          IconButton(
            tooltip: s.t(T.viewOther),
            icon: const Icon(Icons.translate),
            onPressed: () => setState(() => _other = !_other),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: r.total,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, i) =>
            ReviewCard(index: i, result: r, lang: lang),
      ),
    );
  }
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.index, required this.result, required this.lang});
  final int index;
  final QuizResult result;
  final Lang lang;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final q = result.questions[index];
    final choice = result.choices[index];
    final bookmarked = app.isBookmarked(q.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('${index + 1}.',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(child: QuestionTags(question: q)),
              IconButton(
                tooltip: s.t(bookmarked ? T.removeBookmark : T.bookmark),
                icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () => app.toggleBookmark(q),
              ),
              IconButton(
                tooltip: s.t(T.report),
                icon: const Icon(Icons.flag_outlined),
                onPressed: () => showReportSheet(context, q),
              ),
            ]),
            const SizedBox(height: 8),
            Text(q.q.of(lang),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.35)),
            const SizedBox(height: 10),
            for (var o = 0; o < 4; o++) ...[
              OptionButton(
                index: o,
                text: q.options[o].of(lang),
                semanticLabel: optionSemantics(s, o, q.options[o].of(lang)),
                state: o == q.answer
                    ? OptionState.correct
                    : o == choice
                        ? OptionState.wrong
                        : OptionState.dimmed,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              choice == null
                  ? s.t(T.notAnswered)
                  : s.f(T.yourAnswer, {
                      'answer': '${OptionButton.letters[choice]}. ${q.options[choice].of(lang)}'
                    }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            AnswerExplanation(
                question: q, choice: choice, lang: lang, onOpenSource: openLink),
          ],
        ),
      ),
    );
  }
}
