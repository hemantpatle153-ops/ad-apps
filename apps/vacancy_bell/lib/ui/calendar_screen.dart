import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../logic/calendar.dart';
import '../models/post.dart';
import 'home_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Map<String, PostDetail>? _details;
  bool _savedOnly = false;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).repo.allCachedPosts().then((d) {
      if (mounted) setState(() => _details = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    final today = app.today;
    final saved = app.settings.saved;
    final savedIds = {for (final p in saved) p.id};
    final posts = <String, PostSummary>{
      if (!_savedOnly)
        for (final p in app.index?.posts ?? const <PostSummary>[]) p.id: p,
      for (final p in saved) p.id: p,
    };
    final months = groupByMonth(
        buildCalendar(posts.values, _details ?? app.repo.loadedPosts, today: today));

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(L.calendarTitle)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              ChoiceChip(
                label: Text(s.t(L.navJobs)),
                selected: !_savedOnly,
                onSelected: (_) => setState(() => _savedOnly = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(s.t(L.navSaved)),
                selected: _savedOnly,
                onSelected: (_) => setState(() => _savedOnly = true),
              ),
            ]),
          ),
        ),
      ),
      body: months.isEmpty
          ? StateMessage(
              icon: Icons.event_available_outlined,
              title: s.t(L.calendarEmpty),
              body: s.t(L.calendarEmptyHint),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final m in months) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Semantics(
                      header: true,
                      child: Text(s.monthYear(m.year, m.month),
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  for (final e in m.events)
                    _EventTile(event: e, saved: savedIds.contains(e.post.id)),
                ],
              ],
            ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.saved});
  final CalendarEvent event;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final days = app.today.daysUntil(event.date);
    final urgent = event.kind == CalendarKind.lastDate && days <= 3;
    final when = days == 0
        ? s.t(L.today)
        : days == 1
            ? s.t(L.tomorrow)
            : s.weekday(event.date);
    final kindLabel = event.label != null ? s.text(event.label) : s.calendarKind(event.kind);
    return ListTile(
      onTap: () => openPost(context, event.post),
      leading: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: urgent ? status.urgent : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${event.date.day}',
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: urgent ? status.onUrgent : theme.colorScheme.onPrimaryContainer)),
          Text(when,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: urgent ? status.onUrgent : theme.colorScheme.onPrimaryContainer)),
        ]),
      ),
      title: Text(s.text(event.post.title), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(kindLabel),
      trailing: saved ? Icon(Icons.bookmark, color: theme.colorScheme.primary, size: 20) : null,
    );
  }
}
