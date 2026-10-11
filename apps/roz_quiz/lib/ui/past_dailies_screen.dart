import 'package:flutter/material.dart';

import '../core/day.dart';
import '../core/session.dart';
import '../l10n/strings.dart';
import 'launch.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Daily quizzes of earlier days (from the feed index), playable for
/// practice; they don't change the streak.
class PastDailiesScreen extends StatefulWidget {
  const PastDailiesScreen({super.key});

  @override
  State<PastDailiesScreen> createState() => _PastDailiesScreenState();
}

class _PastDailiesScreenState extends State<PastDailiesScreen> {
  Day? _loading;

  Future<void> _open(Day day) async {
    final app = AppScope.read(context);
    final s = app.s;
    setState(() => _loading = day);
    final r = await app.dailyFor(day);
    if (!mounted) return;
    setState(() => _loading = null);
    final quiz = r.value;
    if (quiz == null) {
      showSnack(context, s.t(T.errorOffline));
      return;
    }
    final title = s.f(T.dayLabel, {'date': s.date(day.year, day.month, day.day)});
    final record = app.store.days[day.key];
    if (record != null) {
      await openDailyReview(context, quiz.questions, record);
    } else {
      await openQuiz(context,
          mode: QuizMode.daily, questions: quiz.questions, title: title, dailyDate: day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final today = app.today;
    final days = {
      ...?app.feedIndex?.daily.where((d) => d.isBefore(today)),
      for (final d in app.store.playedDays) if (d.isBefore(today)) d,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(title: Text(s.t(T.pastDailies))),
      body: days.isEmpty
          ? StateMessage(
              icon: Icons.calendar_month,
              title: s.t(T.pastDailies),
              body: s.t(T.pastDailiesEmpty),
              actionLabel: s.t(T.retry),
              onAction: () => app.loadIndex(refresh: true),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = days[i];
                final rec = app.store.days[d.key];
                return Card(
                  child: ListTile(
                    minVerticalPadding: 14,
                    leading: CircleAvatar(
                      backgroundColor: rec != null
                          ? context.quiz.correctSoft
                          : context.colors.surfaceContainerHighest,
                      child: Icon(rec != null ? Icons.check : Icons.quiz_outlined,
                          color: rec != null ? context.quiz.correct : null),
                    ),
                    title: Text(s.date(d.year, d.month, d.day),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: rec != null
                        ? Text('${rec.correct}/${rec.total}')
                        : Text(s.t(T.dailyQuiz)),
                    trailing: _loading == d
                        ? const SizedBox.square(
                            dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(rec != null ? Icons.fact_check_outlined : Icons.play_arrow),
                    onTap: _loading == null ? () => _open(d) : null,
                  ),
                );
              },
            ),
    );
  }
}
