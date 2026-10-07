import 'package:flutter/material.dart';

import '../core/day.dart';
import '../core/models.dart';
import '../core/selection.dart';
import '../core/session.dart';
import '../core/stats.dart';
import '../core/streak.dart';
import '../l10n/strings.dart';
import 'practice_tab.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

class ProgressTab extends StatelessWidget {
  const ProgressTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final stats = app.store.stats;
    final total = stats.total;
    final st = app.streak;
    final today = app.today;
    final lv = app.level;
    final scores = {
      for (final e in app.store.days.entries) Day.tryParse(e.key)!: e.value.fraction
    };
    final weeks = heatmapWeeks(today, 15, scores);
    final last = stats.lastDays(today, 14);
    final subjects = [
      for (final sub in kSubjects)
        if ((stats.bySubject[sub]?.answered ?? 0) > 0) sub
    ];
    final weak = stats.weakSubjects();
    final timeSpent = Duration(milliseconds: total.timeMs);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              ScoreRing(
                fraction: lv.progress,
                size: 72,
                color: context.colors.tertiary,
                semanticLabel: s.f(T.level, {'n': lv.level}),
                center: Text('${lv.level}',
                    style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.f(T.level, {'n': lv.level}),
                        style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    Text(s.f(T.xp, {'n': app.store.xp})),
                    Text(
                        s.f(T.xpToNext,
                            {'n': lv.xpForNext - lv.xpIntoLevel, 'level': lv.level + 1}),
                        style: context.text.bodySmall
                            ?.copyWith(color: context.colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TileGrid(minTileWidth: 150, children: [
          StatTile(
              icon: Icons.local_fire_department,
              value: '${st.current}',
              label: s.f(T.streakDays, {'n': st.current}),
              color: context.quiz.streak),
          StatTile(
              icon: Icons.emoji_events,
              value: '${st.best}',
              label: s.f(T.bestStreak, {'n': st.best}),
              color: context.colors.tertiary),
          StatTile(
              icon: Icons.quiz,
              value: '${total.answered}',
              label: s.t(T.totalAnswered)),
          StatTile(
              icon: Icons.track_changes,
              value: '${(total.accuracy * 100).round()}%',
              label: s.t(T.overallAccuracy),
              color: context.quiz.correct),
          StatTile(
              icon: Icons.timer_outlined,
              value: formatClock(timeSpent),
              label: s.t(T.timeSpent)),
          StatTile(
              icon: Icons.task_alt,
              value: '${stats.quizzes}',
              label: s.t(T.quizzesPlayed)),
        ]),
        SectionTitle(s.t(T.daysPlayed)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Heatmap(
              weeks: weeks,
              semanticLabel: '${s.t(T.daysPlayed)}: ${st.totalDays}',
              lessLabel: s.t(T.less),
              moreLabel: s.t(T.more),
            ),
          ),
        ),
        SectionTitle(s.t(T.last14Days)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MiniBarChart(
              values: [for (final (_, t) in last) t.answered.toDouble()],
              highlights: [for (final (_, t) in last) t.correct.toDouble()],
              labels: [for (final (d, _) in last) '${d.day}'],
              semanticLabel:
                  '${s.t(T.last14Days)}: ${last.fold<int>(0, (a, e) => a + e.$2.answered)}',
            ),
          ),
        ),
        SectionTitle(s.t(T.subjectAccuracy)),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: subjects.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(s.t(T.noStatsYet)),
                  )
                : Column(children: [
                    for (final sub in subjects)
                      AccuracyRow(
                        icon: subjectIcon(sub),
                        color: subjectColor(sub),
                        label: s.subject(sub),
                        fraction: stats.bySubject[sub]!.accuracy,
                        trailing:
                            '${(stats.bySubject[sub]!.accuracy * 100).round()}% · ${stats.bySubject[sub]!.correct}/${stats.bySubject[sub]!.answered}',
                      ),
                  ]),
          ),
        ),
        SectionTitle(s.t(T.weakTopics)),
        Card(
          child: weak.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text(s.t(T.weakNone)))
              : Column(children: [
                  for (final sub in weak)
                    ListTile(
                      leading: Icon(subjectIcon(sub), color: subjectColor(sub)),
                      title: Text(s.subject(sub)),
                      subtitle: Text('${(stats.bySubject[sub]!.accuracy * 100).round()}%'),
                      trailing: TextButton(
                        onPressed: () => showPracticeSheet(context,
                            title: s.subject(sub), base: PracticeFilter(subject: sub)),
                        child: Text(s.t(T.practiceThis)),
                      ),
                    ),
                ]),
        ),
        SectionTitle(s.t(T.badges)),
        TileGrid(minTileWidth: 150, children: [
          for (final b in Achievement.values) _BadgeTile(badge: b, earned: app.store.badges.contains(b)),
        ]),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.earned});
  final Achievement badge;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final (name, desc) = context.s.badge(badge);
    final col = earned ? context.quiz.marked : context.colors.outline;
    return Semantics(
      label: '$name. $desc${earned ? ' ✓' : ''}',
      excludeSemantics: true,
      child: Card(
        color: earned ? null : context.colors.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(earned ? Icons.military_tech : Icons.lock_outline, color: col, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(desc,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
