import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/selection.dart';
import '../core/session.dart';
import '../l10n/strings.dart';
import 'question_view.dart';
import 'report_sheet.dart';
import 'result_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

const kMockLengths = [25, 50, 100];

/// Time allowed per mock question (SSC-style: 60 minutes for 100).
const kMockSecondsPerQuestion = 36;

class MockSetupScreen extends StatefulWidget {
  const MockSetupScreen({super.key});

  @override
  State<MockSetupScreen> createState() => _MockSetupScreenState();
}

class _MockSetupScreenState extends State<MockSetupScreen> {
  String? _exam;
  int _count = 25;
  NegativeMarking? _negative;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.read(context);
    _negative ??= app.settings.mockNegative;
    final targets = app.settings.targetExams;
    if (_exam == null && targets.isNotEmpty) _exam = targets.first;
  }

  void _start() {
    final app = AppScope.read(context);
    final s = app.s;
    final picked = app.pickMock(_count, exam: _exam).questions;
    if (picked.isEmpty) {
      showSnack(context, s.t(T.notEnough));
      return;
    }
    if (_negative != app.settings.mockNegative) {
      app.updateSettings((st) => st.mockNegative = _negative!);
    }
    final session = QuizSession(
      mode: QuizMode.mock,
      questions: picked,
      totalLimit: Duration(seconds: picked.length * kMockSecondsPerQuestion),
      negative: _negative!,
    );
    final title = '${s.t(T.mockTests)} · ${_exam == null ? s.t(T.anyExam) : s.exam(_exam!)}';
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MockTestScreen(session: session, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final targets = app.settings.targetExams;
    final exams = [...targets, for (final e in kExams) if (!targets.contains(e)) e];
    final available = app.countFor(PracticeFilter(exam: _exam));
    final n = available < _count ? available : _count;
    return Scaffold(
      appBar: AppBar(title: Text(s.t(T.mockSetup))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionTitle(s.t(T.exam)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: Text(s.t(T.anyExam)),
              selected: _exam == null,
              onSelected: (_) => setState(() => _exam = null),
            ),
            for (final e in exams)
              ChoiceChip(
                avatar: Icon(examIcon(e), size: 18),
                label: Text(s.exam(e)),
                selected: _exam == e,
                onSelected: (_) => setState(() => _exam = e),
              ),
          ]),
          SectionTitle(s.t(T.testLength)),
          Wrap(spacing: 8, children: [
            for (final c in kMockLengths)
              ChoiceChip(
                label: Text('$c'),
                selected: _count == c,
                onSelected: (_) => setState(() => _count = c),
              ),
          ]),
          SectionTitle(s.t(T.negativeMarking)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final neg in NegativeMarking.values)
              ChoiceChip(
                label: Text(s.negative(neg)),
                selected: _negative == neg,
                onSelected: (_) => setState(() => _negative = neg),
              ),
          ]),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(Icons.quiz_outlined, s.f(T.available, {'n': available})),
                  _InfoRow(Icons.timer_outlined,
                      '${s.t(T.timeLimit)}: ${s.f(T.minutes, {'n': (n * kMockSecondsPerQuestion / 60).ceil()})}'),
                  _InfoRow(Icons.remove_circle_outline,
                      s.f(T.negativeInfo, {'value': s.negative(_negative!)})),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('startMock'),
            onPressed: available == 0 ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(s.t(T.startTest)),
          ),
          if (available == 0) ...[
            const SizedBox(height: 12),
            Text(s.t(T.notEnough), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

/// A timed test: answers can be changed, marked for review or cleared
/// until submit; the palette shows the state of every question.
class MockTestScreen extends StatefulWidget {
  const MockTestScreen({super.key, required this.session, required this.title});
  final QuizSession session;
  final String title;

  @override
  State<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends State<MockTestScreen> with WidgetsBindingObserver {
  Timer? _timer;
  bool _active = true;
  bool _finishing = false;
  bool _other = false;

  QuizSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A real exam clock keeps running; so does this one, except that a
    // phone call or lock screen should not silently end the test: time
    // counts only while the test is on screen.
    _active = state == AppLifecycleState.resumed;
  }

  void _tick() {
    if (!_active || _finishing || !mounted) return;
    final ev = _s.tick(const Duration(seconds: 1));
    setState(() {});
    if (ev == TickEvent.timeUp) {
      showSnack(context, AppScope.read(context).s.t(T.timeUpSubmitted));
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _timer?.cancel();
    final app = AppScope.read(context);
    final result = _s.submit();
    final outcome = await app.finishQuiz(result);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ResultScreen(result: result, outcome: outcome, title: widget.title)));
  }

  Future<void> _confirmSubmit() async {
    final s = AppScope.read(context).s;
    final c = _s.paletteCounts();
    final answered = c[PaletteStatus.answered]! + c[PaletteStatus.answeredMarked]!;
    final marked = c[PaletteStatus.marked]! + c[PaletteStatus.answeredMarked]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t(T.submitConfirmTitle)),
        content: SingleChildScrollView(
          child: Text(s.f(T.submitConfirmBody,
              {'a': answered, 'b': _s.length - answered, 'c': marked})),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t(T.cancel))),
          FilledButton(
              key: const ValueKey('confirmSubmit'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t(T.submit))),
        ],
      ),
    );
    if (ok == true) await _finish();
  }

  Future<bool> _confirmExit() async {
    final s = AppScope.read(context).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t(T.exitQuizTitle)),
        content: Text(s.t(T.exitQuizBody)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t(T.stay))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t(T.leave))),
        ],
      ),
    );
    return ok ?? false;
  }

  void _openPalette() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => PaletteSheet(
        session: _s,
        onPick: (i) {
          Navigator.pop(ctx);
          setState(() => _s.goTo(i));
        },
        onSubmit: () {
          Navigator.pop(ctx);
          _confirmSubmit();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final q = _s.question;
    final st = _s.state;
    final lang = _other ? app.lang.other : app.lang;
    final left = _s.totalTimeLeft;
    final low = left != null && left.inSeconds <= 60;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmExit()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: s.t(T.close),
            icon: const Icon(Icons.close),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (await _confirmExit()) nav.pop();
            },
          ),
          title: left == null
              ? Text(widget.title)
              : Semantics(
                  label: s.t(T.timeLimit),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer_outlined,
                        color: low ? context.quiz.wrong : context.colors.primary),
                    const SizedBox(width: 6),
                    Text(formatClock(left),
                        style: TextStyle(
                            color: low ? context.quiz.wrong : null,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ),
          actions: [
            IconButton(
              tooltip: s.t(T.viewOther),
              icon: const Icon(Icons.translate),
              onPressed: () => setState(() => _other = !_other),
            ),
            IconButton(
              key: const ValueKey('palette'),
              tooltip: s.t(T.palette),
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: _openPalette,
            ),
            TextButton(
              key: const ValueKey('submitTest'),
              onPressed: _confirmSubmit,
              child: Text(s.t(T.submit)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SoftProgress(value: _s.answeredCount / _s.length),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(s.f(T.questionOf, {'n': _s.current + 1, 'total': _s.length}),
                            style: context.text.titleSmall
                                ?.copyWith(color: context.colors.onSurfaceVariant)),
                      ),
                      if (st.marked)
                        Tag(s.t(T.legendMarked), icon: Icons.flag, color: context.quiz.marked),
                      IconButton(
                        tooltip: s.t(T.report),
                        icon: const Icon(Icons.flag_outlined),
                        onPressed: () => showReportSheet(context, q),
                      ),
                    ]),
                    QuestionTags(question: q),
                    const SizedBox(height: 12),
                    QuestionText(question: q, lang: lang),
                    const SizedBox(height: 18),
                    for (var o = 0; o < 4; o++) ...[
                      OptionButton(
                        key: ValueKey('option$o'),
                        index: o,
                        text: q.options[o].of(lang),
                        semanticLabel: optionSemantics(s, o, q.options[o].of(lang)),
                        state: st.selected == o ? OptionState.selected : OptionState.idle,
                        onTap: () => setState(() => _s.answer(o)),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              _MockControls(
                s: s,
                session: _s,
                onChanged: () => setState(() {}),
                onLastSaved: _confirmSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MockControls extends StatelessWidget {
  const _MockControls({
    required this.s,
    required this.session,
    required this.onChanged,
    required this.onLastSaved,
  });

  final S s;
  final QuizSession session;
  final VoidCallback onChanged;
  final VoidCallback onLastSaved;

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('mark'),
              onPressed: () {
                session.toggleMark();
                if (session.state.marked) session.next();
                onChanged();
              },
              icon: Icon(st.marked ? Icons.flag : Icons.outlined_flag,
                  color: context.quiz.marked),
              label: Text(s.t(st.marked ? T.unmark : T.markReview),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('clear'),
              onPressed: st.answered
                  ? () {
                      session.clear();
                      onChanged();
                    }
                  : null,
              child: Text(s.t(T.clearResponse), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          IconButton.outlined(
            tooltip: s.t(T.previous),
            onPressed: session.isFirst
                ? null
                : () {
                    session.previous();
                    onChanged();
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const ValueKey('saveNext'),
              onPressed: () {
                if (session.isLast) {
                  onLastSaved();
                } else {
                  session.next();
                  onChanged();
                }
              },
              child: Text(s.t(session.isLast ? T.submitTest : T.saveNext)),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Numbered grid coloured by [PaletteStatus], with a legend and submit.
class PaletteSheet extends StatelessWidget {
  const PaletteSheet({
    super.key,
    required this.session,
    required this.onPick,
    required this.onSubmit,
  });

  final QuizSession session;
  final void Function(int index) onPick;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final counts = session.paletteCounts();
    final legend = {
      PaletteStatus.answered: T.legendAnswered,
      PaletteStatus.notAnswered: T.legendNotAnswered,
      PaletteStatus.notVisited: T.legendNotVisited,
      PaletteStatus.marked: T.legendMarked,
      PaletteStatus.answeredMarked: T.legendAnsweredMarked,
    };
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(s.t(T.palette),
              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            for (final e in legend.entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                _PaletteDot(status: e.key, size: 18),
                const SizedBox(width: 6),
                Text('${s.t(e.value)} (${counts[e.key]})', style: context.text.bodySmall),
              ]),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < session.length; i++)
              Semantics(
                button: true,
                label: '${i + 1}: ${s.t(legend[session.status(i)]!)}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onPick(i),
                  child: _PaletteDot(
                    status: session.status(i),
                    size: 48,
                    label: '${i + 1}',
                    current: i == session.current,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          FilledButton(onPressed: onSubmit, child: Text(s.t(T.submitTest))),
        ],
      ),
    );
  }
}

class _PaletteDot extends StatelessWidget {
  const _PaletteDot({required this.status, required this.size, this.label, this.current = false});
  final PaletteStatus status;
  final double size;
  final String? label;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final q = context.quiz;
    final c = context.colors;
    final (Color bg, Color fg) = switch (status) {
      PaletteStatus.answered => (q.correct, q.onCorrect),
      PaletteStatus.notAnswered => (q.wrong, q.onWrong),
      PaletteStatus.notVisited => (c.surfaceContainerHighest, c.onSurfaceVariant),
      PaletteStatus.marked => (q.marked, Colors.white),
      PaletteStatus.answeredMarked => (q.marked, Colors.white),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: current ? Border.all(color: c.onSurface, width: 2.5) : null,
      ),
      child: Stack(alignment: Alignment.center, children: [
        if (label != null)
          Text(label!, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
        if (status == PaletteStatus.answeredMarked)
          Positioned(
            right: size * 0.08,
            bottom: size * 0.08,
            child: Icon(Icons.check_circle, size: size * 0.3, color: q.correct),
          ),
      ]),
    );
  }
}
