import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../logic/job_query.dart';
import 'home_screen.dart';
import 'post_card.dart';
import 'scope.dart';
import 'widgets.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    // Soonest last date first; closed ones sink to the end.
    final posts = [...app.settings.saved]..sort(closingSoonComparator(app.today));
    return Scaffold(
      appBar: AppBar(title: Text(s.t(L.savedTitle))),
      body: posts.isEmpty
          ? StateMessage(
              icon: Icons.bookmark_border,
              title: s.t(L.savedEmpty),
              body: s.t(L.savedEmptyHint),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = posts[i];
                return Dismissible(
                  key: ValueKey('saved-${p.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                  onDismissed: (_) async {
                    final hadReminder = app.hasReminder(p.id);
                    await app.setSaved(p, false);
                    if (!context.mounted) return;
                    context.toast(
                      s.t(L.removed),
                      action: SnackBarAction(
                        label: s.t(L.undo),
                        onPressed: () async {
                          await app.setSaved(p, true);
                          if (hadReminder) await app.setReminder(p, true);
                        },
                      ),
                    );
                  },
                  child: PostCard(post: p, showType: true, onTap: () => openPost(context, p)),
                );
              },
            ),
    );
  }
}
