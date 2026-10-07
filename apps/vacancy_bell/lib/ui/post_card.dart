import 'package:flutter/material.dart';

import '../core/ymd.dart';
import '../l10n/s.dart';
import '../l10n/strings.dart';
import '../logic/eligibility.dart';
import '../models/post.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// "3 days left", "Closed", ... with its colours.
({String label, Color? bg, Color? fg, IconData icon}) deadlineChip(
    BuildContext context, S s, Ymd? lastDate, Ymd today) {
  final status = StatusColors.of(context);
  final d = Deadline.of(lastDate, today);
  final scheme = Theme.of(context).colorScheme;
  return switch (d.urgency) {
    Urgency.unknown => (
        label: s.t(L.lastDateUnknown),
        bg: null,
        fg: null,
        icon: Icons.event_note_outlined
      ),
    Urgency.closed => (
        label: s.t(L.closed),
        bg: scheme.surfaceContainerHighest,
        fg: scheme.onSurfaceVariant,
        icon: Icons.lock_clock_outlined
      ),
    Urgency.lastDay => (
        label: s.t(L.lastDayToday),
        bg: status.urgent,
        fg: status.onUrgent,
        icon: Icons.alarm
      ),
    Urgency.urgent => (
        label: d.daysLeft == 1 ? s.t(L.oneDayLeft) : s.t(L.daysLeft, {'n': d.daysLeft}),
        bg: status.urgent,
        fg: status.onUrgent,
        icon: Icons.alarm
      ),
    Urgency.soon || Urgency.open => (
        label: s.t(L.lastDateOn, {'date': s.date(lastDate!)}),
        bg: scheme.primaryContainer.withValues(alpha: 0.55),
        fg: scheme.onPrimaryContainer,
        icon: Icons.event_outlined
      ),
  };
}

/// The eligibility badge, or null when there is nothing to say.
Widget? eligibilityPill(BuildContext context, S s, EligibilityResult e) {
  if (e.profileMissing) return null;
  final status = StatusColors.of(context);
  return switch (e.overall) {
    Verdict.yes => Pill(
        label: s.t(L.eligibleYes),
        icon: Icons.verified_outlined,
        background: status.success,
        foreground: status.onSuccess),
    Verdict.no => Pill(
        label: s.t(e.qualification == Verdict.no ? L.eligibleNoQual : L.eligibleNoAge),
        icon: Icons.block,
        background: status.urgent,
        foreground: status.onUrgent),
    Verdict.unknown => Pill(label: s.t(L.eligibleCheck), icon: Icons.help_outline),
  };
}

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.onTap, this.showType = false});
  final PostSummary post;
  final VoidCallback onTap;

  /// Show the post type (in mixed lists such as Saved).
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    final today = app.today;
    final status = StatusColors.of(context);
    final d = Deadline.of(post.lastDate, today);
    final chip = deadlineChip(context, s, post.lastDate, today);
    final isNew = isPostedToday(post.postedAt, today);
    final saved = app.isSaved(post.id);
    final elig = eligibilityPill(context, s, app.eligibilityOf(post));
    final quals = post.qualifications.take(3).toList();
    final title = s.text(post.title);
    final org = s.text(post.org);

    return Opacity(
      opacity: d.isClosed ? 0.72 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isNew)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Pill(
                                label: s.t(L.badgeNew),
                                icon: Icons.notifications_active_outlined,
                                background: status.accent,
                                foreground: status.onAccent,
                              ),
                            ),
                          Text(title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                          if (org.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(org,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: saved ? s.t(L.unsave) : s.t(L.save),
                      icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border,
                          color: saved ? theme.colorScheme.primary : null),
                      onPressed: () => app.setSaved(post, !saved),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(
                        label: chip.label,
                        icon: chip.icon,
                        background: chip.bg,
                        foreground: chip.fg,
                      ),
                      if (post.totalPosts != null)
                        Pill(
                          label: s.t(L.postsCount, {'n': S.number(post.totalPosts!)}),
                          icon: Icons.groups_2_outlined,
                        ),
                      for (final q in quals) Pill(label: s.qualification(q)),
                      if (showType) Pill(label: s.postType(post.type)),
                      if (elig != null) elig,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
