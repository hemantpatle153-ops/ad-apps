import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../core/day.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../data/feed_client.dart';
import '../data/repository.dart';
import '../l10n/strings.dart';
import 'launch.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Current affairs: 60-word notes as swipe cards for a chosen day, then
/// that day's quiz.
class CurrentAffairsTab extends StatefulWidget {
  const CurrentAffairsTab({super.key});

  @override
  State<CurrentAffairsTab> createState() => _CurrentAffairsTabState();
}

class _CurrentAffairsTabState extends State<CurrentAffairsTab> {
  Day? _day;
  Loaded<CaDay>? _data;
  bool _loading = false;
  int _page = 0;
  final _pages = PageController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_day == null) {
      _day = AppScope.read(context).today;
      _load();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final day = _day!;
    setState(() {
      _loading = true;
      _page = 0;
    });
    final app = AppScope.read(context);
    Loaded<CaDay> r;
    try {
      r = await app.currentAffairs(day, refresh: refresh);
    } catch (_) {
      r = const Loaded.failed(FeedErrorKind.badData);
    }
    if (!mounted || day != _day) return;
    setState(() {
      _data = r;
      _loading = false;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  bool _turning = false;

  /// Moves one card up or down (used when a long note is dragged past its
  /// end, where the PageView itself doesn't get the drag).
  Future<void> _turn(int delta) async {
    if (_turning || !_pages.hasClients) return;
    final cards = (_data?.value?.notes.length ?? 0) + 1;
    final target = _page + delta;
    if (target < 0 || target >= cards) return;
    _turning = true;
    await _pages.animateToPage(target,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    _turning = false;
  }

  List<Day> _days() {
    final app = context.app;
    final today = app.today;
    final fromIndex = app.feedIndex?.currentAffairs ?? const <Day>[];
    final set = <Day>{
      ...fromIndex.where((d) => !d.isAfter(today)),
      for (var i = 0; i < 7; i++) today.addDays(-i),
    };
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final app = context.app;
    final days = _days().take(30).toList();
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = days[i];
              return ChoiceChip(
                label: Text(d == app.today
                    ? s.t(T.tabToday)
                    : s.date(d.year, d.month, d.day, withYear: false)),
                selected: d == _day,
                onSelected: (_) {
                  if (d == _day) return;
                  setState(() => _day = d);
                  _load();
                },
              );
            },
          ),
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final s = context.s;
    final data = _data;
    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data == null || !data.hasValue) {
      final offline = data?.error == FeedErrorKind.offline;
      return StateMessage(
        icon: offline ? Icons.cloud_off : Icons.newspaper,
        title: offline ? s.t(T.errorOffline) : s.t(T.caEmpty),
        actionLabel: s.t(T.retry),
        onAction: () => _load(refresh: true),
      );
    }
    final ca = data.value!;
    final cards = ca.notes.length + 1;
    return Column(
      children: [
        if (data.offline)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(s.t(T.offlineBanner),
                style: context.text.bodySmall
                    ?.copyWith(color: context.colors.tertiary)),
          ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            scrollDirection: Axis.vertical,
            itemCount: cards,
            onPageChanged: (p) {
              setState(() => _page = p);
              if (p >= cards - 1) AppScope.read(context).markCaRead(ca.date);
            },
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: i < ca.notes.length
                  ? _NoteCard(
                      note: ca.notes[i],
                      index: i,
                      total: ca.notes.length,
                      onTurn: _turn,
                    )
                  : _QuizCard(day: ca),
            ),
          ),
        ),
        if (_page < cards - 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.keyboard_arrow_up,
                  color: context.colors.onSurfaceVariant),
              Flexible(
                child: Text(s.t(T.caSwipeHint),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: context.text.labelMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant)),
              ),
            ]),
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.index,
    required this.total,
    required this.onTurn,
  });
  final CaNote note;
  final int index;
  final int total;

  /// Called with +1 / -1 when a long note is dragged past its end, so a
  /// swipe on the text still turns the page.
  final void Function(int delta) onTurn;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final tag = note.tags.isEmpty ? null : note.tags.first;
    return Card(
      color: context.colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (tag != null)
                Tag(kSubjects.contains(tag) ? s.subject(tag) : tag,
                    icon: subjectIcon(tag), color: subjectColor(tag)),
              const Spacer(),
              Text('${index + 1}/$total', style: context.text.labelMedium),
            ]),
            const SizedBox(height: 14),
            Expanded(
              child: NotificationListener<OverscrollNotification>(
                onNotification: (n) {
                  if (n.dragDetails != null && n.overscroll.abs() > 4) {
                    onTurn(n.overscroll > 0 ? 1 : -1);
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(note.title.of(app.lang),
                            style: context.text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800, height: 1.25)),
                      ),
                      const SizedBox(height: 14),
                      Text(note.body.of(app.lang),
                          style: context.text.bodyLarge
                              ?.copyWith(height: 1.55, fontSize: 17)),
                    ],
                  ),
                ),
              ),
            ),
            if (note.source != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(s.f(T.sourceLabel, {'name': note.source!.name}),
                      style: context.text.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant)),
                ),
                if (note.source!.url != null)
                  TextButton.icon(
                    onPressed: () => openLink(note.source!.url!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(s.t(T.caReadSource)),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({required this.day});
  final CaDay day;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Card(
      color: context.colors.primaryContainer,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.task_alt, size: 56, color: context.colors.primary),
              const SizedBox(height: 12),
              Text(s.t(T.caAllRead),
                  textAlign: TextAlign.center,
                  style: context.text.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              if (day.questions.isEmpty)
                Text(s.t(T.caNoQuiz))
              else
                FilledButton.icon(
                  key: const ValueKey('caQuiz'),
                  onPressed: () => openQuiz(context,
                      mode: QuizMode.currentAffairs,
                      questions: day.questions,
                      title:
                          '${s.t(T.caTitle)} · ${s.date(day.date.year, day.date.month, day.date.day)}'),
                  icon: const Icon(Icons.quiz),
                  label: Text('${s.t(T.caQuiz)} (${day.questions.length})'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
