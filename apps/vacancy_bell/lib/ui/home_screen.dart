import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/jobs_repository.dart';
import '../l10n/strings.dart';
import '../logic/job_query.dart';
import '../models/post.dart';
import '../models/taxonomy.dart';
import 'calendar_screen.dart';
import 'detail_screen.dart';
import 'filter_sheet.dart';
import 'more_screen.dart';
import 'post_card.dart';
import 'saved_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Order of the tabs on the Jobs page.
const tabTypes = [
  PostType.job,
  PostType.admitCard,
  PostType.result,
  PostType.answerKey,
  PostType.syllabus,
  PostType.admission,
  PostType.notice,
];

void openPost(BuildContext context, PostSummary p) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => DetailScreen(postId: p.id, summary: p),
    settings: RouteSettings(name: '/post/${p.id}'),
  ));
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final pages = [
      const JobsPage(),
      const CalendarScreen(),
      const SavedScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AppConfig.adsEnabled) const BannerAdSlot(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.work_outline),
                  selectedIcon: const Icon(Icons.work),
                  label: s.t(L.navJobs)),
              NavigationDestination(
                  icon: const Icon(Icons.calendar_month_outlined),
                  selectedIcon: const Icon(Icons.calendar_month),
                  label: s.t(L.navCalendar)),
              NavigationDestination(
                  icon: const Icon(Icons.bookmark_border),
                  selectedIcon: const Icon(Icons.bookmark),
                  label: s.t(L.navSaved)),
              NavigationDestination(
                  icon: const Icon(Icons.grid_view_outlined),
                  selectedIcon: const Icon(Icons.grid_view),
                  label: s.t(L.navMore)),
            ],
          ),
        ],
      ),
    );
  }
}

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = AppScope.read(context).query.text;
    _searching = _search.text.isNotEmpty;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setText(String v) {
    final app = AppScope.read(context);
    app.setQuery(app.query.copyWith(text: v));
  }

  void _closeSearch() {
    _search.clear();
    _setText('');
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    final filters = app.query.activeFilters;

    return DefaultTabController(
      length: tabTypes.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: _searching
              ? TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: _setText,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: s.t(L.searchHint),
                    border: InputBorder.none,
                  ),
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: brandSaffron.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.notifications_active, color: brandSaffron, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(child: Text(s.t(L.appName), overflow: TextOverflow.ellipsis)),
                  ],
                ),
          actions: [
            if (_searching)
              IconButton(
                tooltip: s.t(L.clearSearch),
                icon: const Icon(Icons.close),
                onPressed: _closeSearch,
              )
            else
              IconButton(
                tooltip: s.t(L.search),
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _searching = true),
              ),
            IconButton(
              tooltip: s.t(L.filters),
              icon: Badge(
                isLabelVisible: filters > 0,
                label: Text('$filters'),
                child: const Icon(Icons.tune),
              ),
              onPressed: () => showFilterSheet(context),
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            tabs: [for (final t in tabTypes) Tab(text: s.postType(t))],
          ),
        ),
        body: Column(
          children: [
            const _StatusBanner(),
            if (!app.query.isDefault) const _ActiveFilters(),
            Expanded(
              child: TabBarView(
                children: [for (final t in tabTypes) _PostList(type: t)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    if (app.feedIsNewer) {
      return InfoBanner(icon: Icons.system_update, text: s.t(L.feedNewer), warning: true);
    }
    final problem = app.problem;
    if (problem == null || app.index == null || app.loading) return const SizedBox.shrink();
    final at = app.checkedAt;
    final ago = at == null ? '-' : s.ago(at, app.now());
    return InfoBanner(
      icon: problem == FeedProblem.offline ? Icons.cloud_off : Icons.sync_problem,
      text: s.t(problem == FeedProblem.offline ? L.offlineBanner : L.staleBanner, {'ago': ago}),
      actionLabel: s.t(L.retry),
      onAction: app.refresh,
      warning: true,
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final q = app.query;
    final chips = <Widget>[];
    void add(String label, JobQuery next) => chips.add(Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text(label),
            onDeleted: () => app.setQuery(next),
            deleteButtonTooltipMessage: s.t(L.remove),
          ),
        ));
    if (q.sort == SortOrder.closingSoon) add(s.t(L.sortClosing), q.copyWith(sort: SortOrder.newest));
    for (final c in q.categories) {
      add(s.category(c), q.copyWith(categories: {...q.categories}..remove(c)));
    }
    for (final ql in q.qualifications) {
      add(s.qualification(ql), q.copyWith(qualifications: {...q.qualifications}..remove(ql)));
    }
    if (q.state != null) add(s.state(q.state!), q.copyWith(state: () => null));
    if (q.onlyEligible) add(s.t(L.onlyEligible), q.copyWith(onlyEligible: false));
    if (q.hideClosed) add(s.t(L.hideClosed), q.copyWith(hideClosed: false));
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        children: [
          ...chips,
          TextButton(
            onPressed: () => app.setQuery(q.cleared()),
            child: Text(s.t(L.clearAll)),
          ),
        ],
      ),
    );
  }
}

class _PostList extends StatelessWidget {
  const _PostList({required this.type});
  final PostType type;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    if (app.index == null) {
      if (!app.started || app.loading) return SkeletonList(label: s.t(L.loading));
      final problem = app.problem;
      return StateMessage(
        icon: problem == FeedProblem.offline ? Icons.wifi_off : Icons.cloud_off_outlined,
        title: s.t(L.loadErrorTitle),
        body: s.t(switch (problem) {
          FeedProblem.offline => L.errorOffline,
          FeedProblem.badData => L.errorBadData,
          _ => L.errorServer,
        }),
        actionLabel: s.t(L.retry),
        onAction: app.refresh,
      );
    }
    final posts = app.postsOf(type);
    final Widget body;
    if (posts.isEmpty) {
      final filtered = !app.query.isDefault && app.countOf(type) > 0;
      body = StateMessage(
        icon: filtered ? Icons.search_off : Icons.inbox_outlined,
        title: s.t(filtered ? L.emptySearch : L.emptyTab),
        body: s.t(filtered ? L.emptySearchHint : L.emptyTabHint),
        actionLabel: filtered ? s.t(L.clearAll) : null,
        onAction: filtered ? () => app.setQuery(const JobQuery()) : null,
      );
    } else {
      body = ListView.separated(
        key: PageStorageKey('list-${type.wire}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: posts.length + 1,
        separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 4 : 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Semantics(
              liveRegion: true,
              child: Text(
                s.t(L.resultsCount, {'n': posts.length}),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            );
          }
          final p = posts[i - 1];
          return PostCard(post: p, onTap: () => openPost(context, p));
        },
      );
    }
    return RefreshIndicator(onRefresh: app.refresh, child: body);
  }
}
