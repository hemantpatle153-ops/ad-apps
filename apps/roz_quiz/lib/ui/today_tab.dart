import 'package:flutter/material.dart';

import '../core/day.dart';
import '../core/session.dart';
import '../data/repository.dart';
import '../l10n/strings.dart';
import 'launch.dart';
import 'mock_screen.dart';
import 'past_dailies_screen.dart';
import 'saved_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final hour = app.now().toUtc().add(Day.istOffset).hour;
    final greet = hour < 12
        ? T.greetMorning
        : hour < 17
            ? T.greetAfternoon
            : T.greetEvening;
    final daily = app.daily;
    final showOffline = app.offline && daily?.source != DataSource.network;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([app.loadToday(refresh: true), app.loadIndex(refresh: true)]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(s.t(greet),
              style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
          Text(s.t(T.appTagline),
              style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          if (showOffline) ...[
            const SizedBox(height: 12),
            _OfflineBanner(text: s.t(T.offlineBanner)),
          ],
          const SizedBox(height: 16),
          const _DailyCard(),
          const SizedBox(height: 14),
          const _StreakCard(),
          const SizedBox(height: 14),
          const _LevelCard(),
          SectionTitle(s.t(T.quickPractice)),
          TileGrid(minTileWidth: 150, children: [
            _QuickTile(
              icon: Icons.bookmark,
              label: s.t(T.bookmarks),
              count: app.store.bookmarks.length,
              color: context.colors.primary,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SavedScreen(kind: SavedKind.bookmarks))),
            ),
            _QuickTile(
              icon: Icons.replay,
              label: s.t(T.myMistakes),
              count: app.store.mistakes.length,
              color: context.quiz.wrong,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SavedScreen(kind: SavedKind.mistakes))),
            ),
            _QuickTile(
              icon: Icons.assignment,
              label: s.t(T.mockTests),
              color: context.quiz.marked,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const MockSetupScreen())),
            ),
            _QuickTile(
              icon: Icons.calendar_month,
              label: s.t(T.pastDailies),
              color: context.colors.tertiary,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PastDailiesScreen())),
            ),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Text(
              app.lastUpdated == null
                  ? s.t(T.neverUpdated)
                  : s.f(T.updatedAt, {'when': s.ago(app.lastUpdated!, app.now())}),
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(Icons.cloud_off, color: context.colors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: context.colors.onTertiaryContainer)),
          ),
        ]),
      );
}

class _DailyCard extends StatelessWidget {
  const _DailyCard();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final daily = app.daily?.value;
    final record = app.todayRecord;
    final today = app.today;
    final onBrand = Colors.white;
    final count = daily?.questions.length ?? 10;
    final sub = app.daily?.source == DataSource.bundled
        ? s.f(T.dailyOfflineSub, {'n': count})
        : s.f(T.dailyQuizSub, {'n': count});
    final title = daily?.title?.of(app.lang) ?? s.t(T.dailyQuiz);

    Widget action;
    if (app.loadingDaily && daily == null) {
      action = const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
      );
    } else if (daily == null) {
      action = FilledButton.tonal(
        onPressed: () => app.loadToday(refresh: true),
        child: Text(s.t(T.retry)),
      );
    } else if (record != null) {
      action = Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(
          key: const ValueKey('dailyReview'),
          style: FilledButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: kBrand),
          onPressed: () => openDailyReview(context, daily.questions, record),
          child: Text(s.t(T.reviewAnswers)),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70)),
          onPressed: () => openQuiz(context,
              mode: QuizMode.practice, questions: daily.questions, title: title),
          child: Text(s.t(T.practiceAgain)),
        ),
      ]);
    } else {
      action = FilledButton.icon(
        key: const ValueKey('playDaily'),
        style: FilledButton.styleFrom(
            backgroundColor: Colors.white, foregroundColor: kBrand),
        onPressed: () => openQuiz(context,
            mode: QuizMode.daily,
            questions: daily.questions,
            title: title,
            dailyDate: today),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(s.t(T.playNow)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0E9F7E), Color(0xFF0B6E73)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.today, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.date(today.year, today.month, today.day),
                  style: TextStyle(color: onBrand.withValues(alpha: 0.9))),
            ),
            if (record != null)
              const Icon(Icons.verified, color: kAccent),
          ]),
          const SizedBox(height: 10),
          Text(title,
              style: context.text.headlineSmall
                  ?.copyWith(color: onBrand, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            record != null
                ? s.f(T.playedScore, {'score': record.correct, 'total': record.total})
                : sub,
            style: context.text.bodyMedium?.copyWith(color: onBrand.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 16),
          action,
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final st = app.streak;
    final q = context.quiz;
    final today = app.today;
    final monday = today.addDays(1 - today.weekday);
    final played = app.store.playedDays;
    final msg = st.playedToday
        ? T.streakKept
        : st.atRisk
            ? T.streakAtRisk
            : T.streakStart;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.local_fire_department,
                  color: st.current > 0 ? q.streak : context.colors.outline, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.f(T.streakDays, {'n': st.current}),
                        style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    Text(s.f(T.bestStreak, {'n': st.best}),
                        style: context.text.bodySmall
                            ?.copyWith(color: context.colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 7; i++)
                  () {
                    final d = monday.addDays(i);
                    final on = played.contains(d);
                    final isToday = d == today;
                    return Semantics(
                      label: '${s.date(d.year, d.month, d.day)}${on ? ' ✓' : ''}',
                      excludeSemantics: true,
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? q.streak : context.colors.surfaceContainerHighest,
                          shape: BoxShape.circle,
                          border: isToday
                              ? Border.all(color: context.colors.primary, width: 2)
                              : null,
                        ),
                        child: on
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : Text('${d.day}',
                                style: context.text.labelMedium?.copyWith(
                                    color: d.isAfter(today)
                                        ? context.colors.outline
                                        : context.colors.onSurfaceVariant)),
                      ),
                    );
                  }(),
              ],
            ),
            const SizedBox(height: 12),
            Text(s.t(msg),
                style: context.text.bodyMedium?.copyWith(
                    color: st.atRisk ? q.streak : context.colors.onSurfaceVariant,
                    fontWeight: st.atRisk ? FontWeight.w700 : null)),
          ],
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final lv = app.level;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: context.colors.tertiaryContainer,
            child: Text('${lv.level}',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: context.colors.onTertiaryContainer)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(s.f(T.level, {'n': lv.level}),
                        style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Text(s.f(T.xp, {'n': app.store.xp}), style: context.text.labelLarge),
                ]),
                const SizedBox(height: 6),
                SoftProgress(value: lv.progress, color: context.colors.tertiary),
                const SizedBox(height: 4),
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
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (count != null && count! > 0)
                Text('$count',
                    style: context.text.labelLarge?.copyWith(color: color)),
            ]),
          ),
        ),
      );
}
