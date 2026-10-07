import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../core/bi.dart';
import '../core/day.dart';
import '../core/session.dart';
import '../l10n/strings.dart';
import 'question_view.dart';
import 'report_sheet.dart';
import 'result_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// One question per screen with instant feedback: daily, practice,
/// current affairs and revision quizzes.
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.session,
    required this.title,
    this.dailyDate,
  });

  final QuizSession session;
  final String title;

  /// For a Daily Quiz: the day it belongs to (streak only for today).
  final Day? dailyDate;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
  Timer? _timer;
  bool _active = true;
  bool _finishing = false;
  final Set<int> _flipped = {};
  final _scroll = ScrollController();

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
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
  }

  void _tick() {
    if (!_active || _finishing || !mounted) return;
    final ev = _s.tick(const Duration(seconds: 1));
    if (ev == TickEvent.questionTimedOut) {
      answerFeedback(AppScope.read(context), correct: false);
    }
    if (_s.perQuestionLimit != null || ev != TickEvent.none) setState(() {});
  }

  Lang _langFor(int i) {
    final lang = AppScope.read(context).lang;
    return _flipped.contains(i) ? lang.other : lang;
  }

  void _answer(int choice) {
    if (!_s.answer(choice)) return;
    answerFeedback(AppScope.read(context), correct: _s.question.isCorrect(choice));
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      }
    });
  }

  void _next() {
    if (_s.isLast) {
      _finish();
      return;
    }
    _s.next();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {});
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    _timer?.cancel();
    final app = AppScope.read(context);
    final result = _s.submit();
    final outcome = await app.finishQuiz(result, dailyDate: widget.dailyDate);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultScreen(
        result: result,
        outcome: outcome,
        title: widget.title,
        isDaily: widget.dailyDate != null,
      ),
    ));
  }

  Future<bool> _confirmExit() async {
    if (_s.answeredCount == 0) return true;
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

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final i = _s.current;
    final q = _s.question;
    final st = _s.state;
    final lang = _langFor(i);
    final closed = _s.isClosed(i);
    final timeLeft = _s.questionTimeLeft;
    final bookmarked = app.isBookmarked(q.id);

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
          title: Text(s.f(T.questionOf, {'n': i + 1, 'total': _s.length})),
          actions: [
            IconButton(
              tooltip: s.t(T.viewOther),
              icon: const Icon(Icons.translate),
              onPressed: () => setState(() =>
                  _flipped.contains(i) ? _flipped.remove(i) : _flipped.add(i)),
            ),
            IconButton(
              tooltip: s.t(bookmarked ? T.removeBookmark : T.bookmark),
              icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () {
                final added = app.toggleBookmark(q);
                showSnack(context, s.t(added ? T.bookmarkAdded : T.bookmarkRemoved));
              },
            ),
            IconButton(
              tooltip: s.t(T.report),
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => showReportSheet(context, q),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  Expanded(
                    child: Semantics(
                      label: s.f(T.questionOf, {'n': i + 1, 'total': _s.length}),
                      child: SoftProgress(value: (i + (closed ? 1 : 0)) / _s.length),
                    ),
                  ),
                  if (timeLeft != null) ...[
                    const SizedBox(width: 12),
                    _TimerChip(left: timeLeft, total: _s.perQuestionLimit!, label: s),
                  ],
                ]),
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    QuestionTags(question: q),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: KeyedSubtree(
                        key: ValueKey('q$i${lang.name}'),
                        child: QuestionText(question: q, lang: lang),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (var o = 0; o < 4; o++) ...[
                      OptionButton(
                        key: ValueKey('option$o'),
                        index: o,
                        text: q.options[o].of(lang),
                        semanticLabel: optionSemantics(s, o, q.options[o].of(lang)),
                        state: !closed
                            ? OptionState.idle
                            : o == q.answer
                                ? OptionState.correct
                                : o == st.selected
                                    ? OptionState.wrong
                                    : OptionState.dimmed,
                        onTap: closed ? null : () => _answer(o),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (closed) ...[
                      const SizedBox(height: 6),
                      AnswerExplanation(
                        question: q,
                        choice: st.selected,
                        lang: lang,
                        timedOut: st.timedOut,
                        onOpenSource: openLink,
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: closed
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('next'),
                          onPressed: _finishing ? null : _next,
                          child: Text(s.t(_s.isLast ? T.seeResult : T.next)),
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const ValueKey('skip'),
                          onPressed: _next,
                          child: Text(s.t(_s.isLast ? T.finish : T.skip)),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  const _TimerChip({required this.left, required this.total, required this.label});
  final Duration left;
  final Duration total;
  final S label;

  @override
  Widget build(BuildContext context) {
    final secs = left.inSeconds;
    final low = secs <= 10;
    final color = low ? context.quiz.wrong : context.colors.primary;
    return Semantics(
      label: label.f(T.timeLeft, {'s': secs}),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_outlined, size: 18, color: color),
          const SizedBox(width: 4),
          Text(formatClock(left),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontFeatures: const [
                FontFeature.tabularFigures()
              ])),
        ]),
      ),
    );
  }
}
