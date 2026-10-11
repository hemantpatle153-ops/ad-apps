import 'package:flutter/material.dart';

import '../core/session.dart';
import '../l10n/strings.dart';
import 'launch.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

enum SavedKind { bookmarks, mistakes }

/// Bookmarks or "My mistakes": a revision list that can be practised.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key, required this.kind});
  final SavedKind kind;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final mistakes = kind == SavedKind.mistakes;
    final items = mistakes ? app.store.mistakeList : app.store.bookmarkList;
    final title = s.t(mistakes ? T.myMistakes : T.bookmarks);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (mistakes && items.isNotEmpty)
            TextButton(
              onPressed: app.clearMistakes,
              child: Text(s.t(T.clearAll)),
            ),
        ],
      ),
      body: items.isEmpty
          ? StateMessage(
              icon: mistakes ? Icons.emoji_events_outlined : Icons.bookmark_border,
              title: title,
              body: s.t(mistakes ? T.mistakesEmpty : T.bookmarksEmpty),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: items.length + (mistakes ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (mistakes && i == 0) {
                  return Text(s.t(T.mistakesHint),
                      style: context.text.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant));
                }
                final sq = items[mistakes ? i - 1 : i];
                final q = sq.question;
                return Dismissible(
                  key: ValueKey(q.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: context.colors.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.delete_outline, color: context.colors.onErrorContainer),
                  ),
                  onDismissed: (_) => mistakes
                      ? app.removeMistake(q.id)
                      : app.toggleBookmark(q),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Tag(s.subject(q.subject),
                                    icon: subjectIcon(q.subject),
                                    color: subjectColor(q.subject)),
                                const SizedBox(height: 8),
                                Text(q.q.of(app.lang),
                                    style: context.text.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                Text(
                                  '${OptionButton.letters[q.answer]}. ${q.options[q.answer].of(app.lang)}',
                                  style: context.text.bodyMedium?.copyWith(
                                      color: context.quiz.correct,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: s.t(T.remove),
                            icon: const Icon(Icons.close),
                            onPressed: () => mistakes
                                ? app.removeMistake(q.id)
                                : app.toggleBookmark(q),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: items.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('practiceSaved'),
              onPressed: () {
                final qs = [for (final sq in items.take(30)) sq.question]..shuffle();
                openQuiz(context,
                    mode: mistakes ? QuizMode.revision : QuizMode.practice,
                    questions: qs,
                    title: title);
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(s.f(T.practiceThese, {'n': items.length > 30 ? 30 : items.length})),
            ),
    );
  }
}
