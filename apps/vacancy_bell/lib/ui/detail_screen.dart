import 'package:flutter/material.dart';

import '../core/ymd.dart';
import '../data/jobs_repository.dart';
import '../l10n/s.dart';
import '../l10n/strings.dart';
import '../logic/eligibility.dart';
import '../logic/share_text.dart';
import '../models/post.dart';
import '../models/taxonomy.dart';
import 'permission.dart';
import 'post_card.dart';
import 'profile_screen.dart';
import 'report_sheet.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.postId, this.summary});
  final String postId;
  final PostSummary? summary;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  PostDetail? _detail;
  FeedResult<PostDetail>? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    setState(() => _loading = true);
    final cached = await app.repo.cachedPost(widget.postId);
    if (!mounted) return;
    if (cached != null && _detail == null) setState(() => _detail = cached);
    final r = await app.loadPost(widget.postId);
    if (!mounted) return;
    setState(() {
      _result = r;
      if (r.data != null) _detail = r.data;
      _loading = false;
    });
  }

  PostSummary? get _summary =>
      _detail?.summary ?? widget.summary ?? AppScope.read(context).summaryOf(widget.postId);

  Future<void> _open(String url) async {
    final app = AppScope.read(context);
    final ok = await app.services.actions.openUrl(url);
    if (!ok && mounted) context.toast(app.s.t(L.openLinkFailed));
  }

  Future<void> _toggleReminder(PostSummary p) async {
    final app = AppScope.read(context);
    final s = app.s;
    if (app.hasReminder(p.id)) {
      await app.setReminder(p, false);
      if (mounted) context.toast(s.t(L.reminderOff));
      return;
    }
    if (!app.canRemind(p)) {
      context.toast(s.t(L.reminderUnavailable));
      return;
    }
    await ensureNotificationPermission(context);
    await app.setReminder(p, true);
    final (h, m) = app.settings.reminderTime;
    if (mounted) context.toast(s.t(L.reminderOnDetail, {'time': s.time(h, m)}));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final p = _summary;
    if (p == null) {
      // Opened from a notification for a post we know nothing about yet.
      return Scaffold(
        appBar: AppBar(),
        body: _loading
            ? SkeletonList(count: 3, label: s.t(L.loading))
            : StateMessage(
                icon: Icons.cloud_off_outlined,
                title: s.t(_result?.problem == FeedProblem.notFound ? L.postGone : L.detailsFailed),
                body: s.t(L.errorOffline),
                actionLabel: s.t(L.retry),
                onAction: _load,
              ),
      );
    }
    final saved = app.isSaved(p.id);
    final reminder = app.hasReminder(p.id);
    final d = _detail;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: saved ? s.t(L.unsave) : s.t(L.save),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => app.setSaved(p, !saved),
          ),
          IconButton(
            tooltip: s.t(L.share),
            icon: const Icon(Icons.share_outlined),
            onPressed: () => app.services.actions
                .shareText(buildShareText(s, p, detail: d), subject: s.text(p.title)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'report') showReportSheet(context, p.id);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'report',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(s.t(L.reportMistake)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _Header(post: p, detail: d),
            const SizedBox(height: 12),
            _EligibilityCard(post: p, detail: d),
            const SizedBox(height: 12),
            if (d == null) ...[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                _DetailProblem(problem: _result?.problem, onRetry: _load),
              const SizedBox(height: 12),
            ] else
              ..._sections(context, s, d),
            _VerifyNote(onOpen: d?.sourcePageUrl == null ? null : () => _open(d!.sourcePageUrl!)),
            const SizedBox(height: 12),
            if (p.updatedAt != null)
              Center(
                child: Text(
                  s.t(L.lastUpdated, {'time': s.instantIst(p.updatedAt!)}),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => showReportSheet(context, p.id),
                icon: const Icon(Icons.flag_outlined),
                label: Text(s.t(L.reportMistake)),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: reminder
                      ? FilledButton.tonalIcon(
                          onPressed: () => _toggleReminder(p),
                          icon: const Icon(Icons.notifications_active),
                          label: Text(s.t(L.reminderOn), overflow: TextOverflow.ellipsis),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => _toggleReminder(p),
                          icon: const Icon(Icons.notifications_none),
                          label: Text(s.t(L.remindMe), overflow: TextOverflow.ellipsis),
                        ),
                ),
              ),
              if (d?.officialNoticeUrl != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => _open(d!.officialNoticeUrl!),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(s.t(L.seeNotice), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, S s, PostDetail d) {
    final theme = Theme.of(context);
    final gap = const SizedBox(height: 12);
    final out = <Widget>[];
    void add(Widget w) => out
      ..add(w)
      ..add(gap);
    final notice = s.t(L.seeNotice);

    if (d.shortInfo != null) {
      add(SectionCard(
        title: s.t(L.shortInfo),
        icon: Icons.info_outline,
        child: Text(s.text(d.shortInfo), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
      ));
    }
    if (d.importantDates.isNotEmpty) {
      add(SectionCard(
        title: s.t(L.importantDates),
        icon: Icons.event_outlined,
        child: InfoTable(rows: [
          for (final e in d.importantDates)
            (s.text(e.label), e.text != null ? s.text(e.text) : (e.date != null ? s.date(e.date!) : notice)),
        ]),
      ));
    }
    if (d.fees.isNotEmpty) {
      add(SectionCard(
        title: s.t(L.applicationFee),
        icon: Icons.currency_rupee,
        child: InfoTable(rows: [
          for (final f in d.fees)
            (s.text(f.category), f.text != null ? s.text(f.text) : s.rupees(f.amount!)),
        ]),
      ));
    }
    final range = s.ageRange(d.ageMin, d.ageMax);
    if (range != null || d.age.asOn != null || d.age.relaxation != null) {
      add(SectionCard(
        title: s.t(L.ageLimit),
        icon: Icons.cake_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(range ?? notice,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (d.age.asOn != null) ...[
              const SizedBox(height: 4),
              Text(s.t(L.ageAsOn, {'date': s.date(d.age.asOn!)}), style: theme.textTheme.bodyMedium),
            ],
            if (d.age.relaxation != null) ...[
              const SizedBox(height: 10),
              Text(s.t(L.ageRelaxation), style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(s.text(d.age.relaxation), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            ],
          ],
        ),
      ));
    }
    if (d.vacancies.isNotEmpty) {
      add(SectionCard(
        title: s.t(L.vacancyDetails),
        icon: Icons.groups_2_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoTable(
              header: (s.t(L.postName), s.t(L.total)),
              rows: [
                for (final v in d.vacancies)
                  (s.text(v.post), v.total == null ? notice : S.number(v.total!)),
                if (d.vacancies.length > 1 && d.totalPosts != null)
                  (s.t(L.total), S.number(d.totalPosts!)),
              ],
            ),
            for (final v in d.vacancies)
              if (v.breakdownParts.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (d.vacancies.length > 1)
                  Text(s.text(v.post), style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (label, n) in v.breakdownParts) Pill(label: '$label ${S.number(n)}'),
                ]),
              ] else if (v.breakdown != null) ...[
                const SizedBox(height: 8),
                Text(s.text(v.breakdown), style: theme.textTheme.bodySmall),
              ],
          ],
        ),
      ));
    }
    if (d.eligibility != null) {
      add(SectionCard(
        title: s.t(L.eligibility),
        icon: Icons.school_outlined,
        child: Text(s.text(d.eligibility), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
      ));
    }
    if (d.selection.isNotEmpty) {
      add(SectionCard(
        title: s.t(L.selectionProcess),
        icon: Icons.checklist,
        child: Column(
          children: [
            for (var i = 0; i < d.selection.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text('${i + 1}',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.text(d.selection[i]))),
                  ],
                ),
              ),
          ],
        ),
      ));
    }
    if (d.howToApply != null) {
      add(SectionCard(
        title: s.t(L.howToApply),
        icon: Icons.edit_note,
        child: Text(s.text(d.howToApply), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
      ));
    }
    final links = <(String, String, IconData)>[
      if (d.officialNoticeUrl != null)
        (s.t(L.officialNotice), d.officialNoticeUrl!, Icons.picture_as_pdf_outlined),
      for (final l in d.links)
        if (l.url != d.officialNoticeUrl) (s.text(l.label), l.url, Icons.open_in_new),
      if (d.sourcePageUrl != null) (s.t(L.sourcePage), d.sourcePageUrl!, Icons.public),
    ];
    if (links.isNotEmpty) {
      add(SectionCard(
        title: s.t(L.importantLinks),
        icon: Icons.link,
        child: Column(
          children: [
            for (final (label, url, icon) in links)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: theme.colorScheme.primary),
                title: Text(label),
                subtitle: Text(Uri.parse(url).host, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(url),
              ),
          ],
        ),
      ));
    }
    return out;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.post, this.detail});
  final PostSummary post;
  final PostDetail? detail;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    final chip = deadlineChip(context, s, post.lastDate, app.today);
    final total = detail?.totalPosts ?? post.totalPosts;
    final status = StatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (isPostedToday(post.postedAt, app.today))
            Pill(label: s.t(L.badgeNew), background: status.accent, foreground: status.onAccent),
          Pill(label: s.category(post.category)),
          if (post.type != PostType.job) Pill(label: s.postType(post.type)),
        ]),
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: Text(s.text(post.title),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
        ),
        if (post.org.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(s.text(post.org),
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pill(label: chip.label, icon: chip.icon, background: chip.bg, foreground: chip.fg),
          if (total != null)
            Pill(label: s.t(L.postsCount, {'n': S.number(total)}), icon: Icons.groups_2_outlined),
          for (final q in post.qualifications) Pill(label: s.qualification(q)),
        ]),
        if (post.salary != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.payments_outlined, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('${s.t(L.payScale)}: ', style: theme.textTheme.labelLarge),
            Expanded(child: Text(s.text(post.salary), style: theme.textTheme.bodyMedium)),
          ]),
        ],
      ],
    );
  }
}

class _EligibilityCard extends StatelessWidget {
  const _EligibilityCard({required this.post, this.detail});
  final PostSummary post;
  final PostDetail? detail;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final profile = app.settings.profile;
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    if (!profile.canCheckEligibility) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.person_search_outlined),
          title: Text(s.t(L.yourEligibility)),
          subtitle: Text(s.t(L.eligNoProfile)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
        ),
      );
    }
    final e = detail != null
        ? eligibilityForDetail(profile, detail!)
        : eligibilityForSummary(profile, post);
    final asOn = detail?.age.asOn;
    (IconData, Color, String) line(Verdict v, String yes, String no, String unknown) => switch (v) {
          Verdict.yes => (Icons.check_circle, status.onSuccess, yes),
          Verdict.no => (Icons.cancel, status.onUrgent, no),
          Verdict.unknown => (Icons.help, theme.colorScheme.onSurfaceVariant, unknown),
        };
    final qual = line(e.qualification, s.t(L.eligQualYes), s.t(L.eligQualNo), s.t(L.eligQualUnknown));
    final ageYes = e.ageOnDate != null && asOn != null
        ? s.t(e.usedRelaxation ? L.eligAgeRelaxed : L.eligAgeYes,
            {'age': e.ageOnDate, 'date': s.date(asOn), 'n': e.relaxationYears})
        : s.t(L.eligAgeUnknown);
    final age = line(
      e.age,
      ageYes,
      s.t(e.ageProblem == AgeProblem.tooYoung ? L.eligAgeTooYoung : L.eligAgeTooOld),
      s.t(L.eligAgeUnknown),
    );
    final badge = eligibilityPill(context, s, e);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(s.t(L.yourEligibility),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (badge != null) Flexible(child: badge),
            ]),
            const SizedBox(height: 12),
            for (final (icon, color, text) in [qual, age])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text)),
                ]),
              ),
            if (profile.exServiceman && e.age == Verdict.unknown) ...[
              const SizedBox(height: 4),
              Text(s.t(L.exServicemanNote), style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Text(s.t(L.eligDisclaimer),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _DetailProblem extends StatelessWidget {
  const _DetailProblem({required this.problem, required this.onRetry});
  final FeedProblem? problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final text = switch (problem) {
      FeedProblem.offline => s.t(L.detailsOffline),
      FeedProblem.notFound => s.t(L.postGone),
      _ => s.t(L.detailsFailed),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(problem == FeedProblem.offline ? Icons.wifi_off : Icons.error_outline),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton.icon(
                onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(s.t(L.retry))),
          ],
        ),
      ),
    );
  }
}

class _VerifyNote extends StatelessWidget {
  const _VerifyNote({this.onOpen});
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final status = StatusColors.of(context);
    return Card(
      color: status.accent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.verified_user_outlined, color: status.onAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(s.t(L.verifyNote),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: status.onAccent)),
            ),
          ]),
        ),
      ),
    );
  }
}
