import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../config.dart';
import '../core/session.dart';
import '../l10n/strings.dart';
import 'review_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Share text for a result.
String shareTextFor(S s, QuizResult r, {required bool isDaily, required int streak}) {
  final score = r.mode == QuizMode.mock ? formatScore(r.score) : '${r.correct}';
  final total = r.mode == QuizMode.mock ? formatScore(r.maxScore) : '${r.total}';
  return isDaily
      ? s.f(T.shareDaily, {
          'score': score,
          'total': total,
          'streak': streak,
          'link': AppConfig.storeUrl,
        })
      : s.f(T.shareOther, {'score': score, 'total': total, 'link': AppConfig.storeUrl});
}

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.result,
    required this.outcome,
    required this.title,
    this.isDaily = false,
  });

  final QuizResult result;
  final FinishOutcome outcome;
  final String title;
  final bool isDaily;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    if (AppConfig.adsEnabled) {
      // A finished quiz is a natural break.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => AdService.instance.maybeShowInterstitial());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final r = widget.result;
    final o = widget.outcome;
    final q = context.quiz;
    final mock = r.mode == QuizMode.mock;
    final fraction = mock ? r.percent : (r.total == 0 ? 0.0 : r.correct / r.total);
    final headline = r.perfect
        ? s.t(T.perfectScore)
        : fraction >= 0.7
            ? s.t(T.greatJob)
            : fraction >= 0.4
                ? s.t(T.goodTry)
                : s.t(T.keepGoing);
    final celebrate = fraction >= 0.6 || (o.countedForStreak && r.correct > 0);
    final scoreText = mock ? formatScore(r.score) : '${r.correct}';
    final maxText = mock ? formatScore(r.maxScore) : '${r.total}';

    return Scaffold(
      appBar: AppBar(
        title: Text(mock ? s.t(T.mockResult) : s.t(T.resultTitle)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: s.t(T.close),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ScoreRing(
                  fraction: fraction < 0 ? 0 : fraction,
                  color: fraction >= 0.4 ? q.correct : q.wrong,
                  semanticLabel: '${s.t(T.score)} $scoreText / $maxText',
                  center: Column(mainAxisSize: MainAxisSize.min, children: [
                    FittedBox(
                      child: Text(scoreText,
                          style: context.text.displaySmall
                              ?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                    Text('/ $maxText', style: context.text.titleMedium),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Text(headline,
                  textAlign: TextAlign.center,
                  style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(widget.title,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (o.xpGained > 0)
                    Tag(s.f(T.xpGained, {'n': o.xpGained}),
                        icon: Icons.bolt, color: context.colors.tertiary),
                  if (o.countedForStreak)
                    Tag(s.f(T.streakNow, {'n': o.streak.current}),
                        icon: Icons.local_fire_department, color: q.streak),
                  if (o.leveledUp)
                    Tag(s.f(T.levelUp, {'n': o.levelAfter}),
                        icon: Icons.trending_up, color: context.colors.primary),
                  for (final b in o.newBadges)
                    Tag(s.f(T.newBadge, {'name': s.badge(b).$1}),
                        icon: Icons.military_tech, color: q.marked),
                ],
              ),
              const SizedBox(height: 16),
              TileGrid(minTileWidth: 140, children: [
                StatTile(
                    icon: Icons.check_circle,
                    value: '${r.correct}',
                    label: s.t(T.correctCount),
                    color: q.correct),
                StatTile(
                    icon: Icons.cancel,
                    value: '${r.wrong}',
                    label: s.t(T.wrongCount),
                    color: q.wrong),
                StatTile(
                    icon: Icons.skip_next,
                    value: '${r.unanswered}',
                    label: s.t(T.skippedCount),
                    color: context.colors.onSurfaceVariant),
                StatTile(
                    icon: Icons.track_changes,
                    value: '${(r.accuracy * 100).round()}%',
                    label: s.t(T.accuracy)),
                StatTile(
                    icon: Icons.timer_outlined,
                    value: formatClock(Duration(milliseconds: r.durationMs)),
                    label: s.t(T.timeTaken)),
              ]),
              if (mock) ...[
                const SizedBox(height: 12),
                Text(s.f(T.negativeInfo, {'value': s.negative(r.negative)}),
                    textAlign: TextAlign.center, style: context.text.bodySmall),
                SectionTitle(s.t(T.sectionAnalysis)),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(children: [
                      for (final sec in r.sections)
                        AccuracyRow(
                          icon: subjectIcon(sec.subject),
                          color: subjectColor(sec.subject),
                          label: s.subject(sec.subject),
                          fraction: sec.accuracy,
                          trailing:
                              '${sec.correct}/${sec.total} · ${formatScore(sec.score)}',
                        ),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('review'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReviewScreen(result: r))),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(s.t(T.reviewAnswers)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('share'),
                onPressed: () => Hooks.share(shareTextFor(s, r,
                    isDaily: widget.isDaily, streak: o.streak.current)),
                icon: const Icon(Icons.share),
                label: Text(s.t(T.share)),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(s.t(T.backHome)),
              ),
            ],
          ),
          if (celebrate) const Positioned.fill(child: Confetti()),
        ],
      ),
    );
  }
}
