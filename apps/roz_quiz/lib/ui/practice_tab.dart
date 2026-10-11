import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/selection.dart';
import '../core/session.dart';
import '../l10n/strings.dart';
import 'launch.dart';
import 'mock_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

const kPracticeLengths = [10, 20, 30];

class PracticeTab extends StatefulWidget {
  const PracticeTab({super.key});

  @override
  State<PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<PracticeTab> {
  bool _byExam = false;
  bool _downloading = false;

  Future<void> _download() async {
    final app = AppScope.read(context);
    setState(() => _downloading = true);
    final ok = await app.downloadBanks();
    if (!mounted) return;
    setState(() => _downloading = false);
    showSnack(context, app.s.t(ok ? T.downloadDone : T.downloadFailed));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final targets = app.settings.targetExams;
    final exams = [...targets, for (final e in kExams) if (!targets.contains(e)) e];
    final pyqCount = app.countFor(const PracticeFilter(pyqOnly: true));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.offline_pin, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.f(T.questionsOffline, {'n': app.pool.length}),
                        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      app.lastUpdated == null
                          ? s.t(T.neverUpdated)
                          : s.f(T.updatedAt, {'when': s.ago(app.lastUpdated!, app.now())}),
                      style: context.text.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              _downloading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                          dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton.filledTonal(
                      key: const ValueKey('download'),
                      tooltip: s.t(T.downloadMore),
                      onPressed: _download,
                      icon: const Icon(Icons.download),
                    ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _BigAction(
          icon: Icons.assignment,
          color: context.quiz.marked,
          title: s.t(T.mockTests),
          subtitle: s.t(T.mockSub),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const MockSetupScreen())),
        ),
        const SizedBox(height: 10),
        _BigAction(
          icon: Icons.history_edu,
          color: context.colors.tertiary,
          title: s.t(T.pyqTitle),
          subtitle: pyqCount > 0 ? s.f(T.available, {'n': pyqCount}) : s.t(T.pyqSub),
          onTap: () => showPracticeSheet(context,
              title: s.t(T.pyqTitle), base: const PracticeFilter(pyqOnly: true)),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(s.t(T.bySubject)), icon: const Icon(Icons.category)),
            ButtonSegment(value: true, label: Text(s.t(T.byExam)), icon: const Icon(Icons.school)),
          ],
          selected: {_byExam},
          onSelectionChanged: (v) => setState(() => _byExam = v.first),
        ),
        const SizedBox(height: 12),
        TileGrid(minTileWidth: 150, children: [
          if (!_byExam)
            for (final sub in kSubjects)
              _TopicTile(
                key: ValueKey('subject-$sub'),
                icon: subjectIcon(sub),
                color: subjectColor(sub),
                label: s.subject(sub),
                count: app.countFor(PracticeFilter(subject: sub)),
                onTap: () => showPracticeSheet(context,
                    title: s.subject(sub), base: PracticeFilter(subject: sub)),
              )
          else
            for (final e in exams)
              _TopicTile(
                key: ValueKey('exam-$e'),
                icon: examIcon(e),
                color: context.colors.primary,
                label: s.exam(e),
                count: app.countFor(PracticeFilter(exam: e)),
                onTap: () =>
                    showPracticeSheet(context, title: s.exam(e), base: PracticeFilter(exam: e)),
              ),
        ]),
      ],
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(subtitle,
                        style: context.text.bodySmall
                            ?.copyWith(color: context.colors.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label, ${context.s.f(T.available, {'n': count})}',
        excludeSemantics: true,
        child: Card(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(height: 10),
                  Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('$count',
                      style: context.text.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Bottom sheet to choose length, difficulty and previous-year questions.
Future<void> showPracticeSheet(BuildContext context,
        {required String title, required PracticeFilter base}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => PracticeSheet(title: title, base: base, parent: context),
    );

class PracticeSheet extends StatefulWidget {
  const PracticeSheet({super.key, required this.title, required this.base, required this.parent});
  final String title;
  final PracticeFilter base;

  /// Context that stays alive after the sheet closes, to open the quiz.
  final BuildContext parent;

  @override
  State<PracticeSheet> createState() => _PracticeSheetState();
}

class _PracticeSheetState extends State<PracticeSheet> {
  int _count = 10;
  Difficulty? _difficulty;
  late bool _pyq = widget.base.pyqOnly;

  PracticeFilter get _filter => PracticeFilter(
        subject: widget.base.subject,
        exam: widget.base.exam,
        difficulty: _difficulty,
        pyqOnly: _pyq,
      );

  void _start() {
    final app = AppScope.read(context);
    final r = app.pickPractice(_filter, _count);
    if (r.questions.isEmpty) return;
    final parent = widget.parent;
    Navigator.of(context).pop();
    if (r.recycled) showSnack(parent, app.s.t(T.newRound));
    openQuiz(parent, mode: QuizMode.practice, questions: r.questions, title: widget.title);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final available = app.countFor(_filter);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title,
              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          SectionTitle(s.t(T.questionsCount)),
          Wrap(spacing: 8, children: [
            for (final c in kPracticeLengths)
              ChoiceChip(
                label: Text('$c'),
                selected: _count == c,
                onSelected: (_) => setState(() => _count = c),
              ),
          ]),
          SectionTitle(s.t(T.difficulty)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in [null, ...Difficulty.values])
              ChoiceChip(
                label: Text(s.difficulty(d)),
                selected: _difficulty == d,
                onSelected: (_) => setState(() => _difficulty = d),
              ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t(T.pyqOnly)),
            value: _pyq,
            onChanged: (v) => setState(() => _pyq = v),
          ),
          const SizedBox(height: 4),
          Text(
            available == 0
                ? (_pyq ? s.t(T.pyqEmpty) : s.t(T.notEnough))
                : s.f(T.available, {'n': available}),
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('startPractice'),
            onPressed: available == 0 ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(s.t(T.startPractice)),
          ),
        ],
      ),
    );
  }
}
