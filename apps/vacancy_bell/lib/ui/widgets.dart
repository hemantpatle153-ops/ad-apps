import 'package:flutter/material.dart';

import 'theme.dart';

/// Full-area message for empty, offline and error states.
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        // Scrollable so pull-to-refresh works and large text never overflows.
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 34, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (body != null) ...[
                  const SizedBox(height: 8),
                  Text(body!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 20),
                  FilledButton.tonalIcon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grey placeholder blocks that pulse while the list loads.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 6, this.label = 'Loading'});
  final int count;
  final String label;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6)),
        );
    return Semantics(
      label: widget.label,
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: widget.count,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(double.infinity, 16),
                  const SizedBox(height: 8),
                  bar(180, 12),
                  const SizedBox(height: 14),
                  Row(children: [bar(80, 24), const SizedBox(width: 8), bar(64, 24)]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded label used on cards ("New", "3 days left", "Graduate").
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.background,
    this.foreground,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = foreground ?? scheme.onSurfaceVariant;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background ?? scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled card section on the detail screen.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.icon});
  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Two-column rows (label | value) that wrap instead of overflowing.
class InfoTable extends StatelessWidget {
  const InfoTable({super.key, required this.rows, this.header});
  final List<(String, String)> rows;
  final (String, String)? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
    Widget row(String a, String b, {bool head = false}) {
      final style = head
          ? theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)
          : theme.textTheme.bodyMedium;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: Text(a, style: style)),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Text(b,
                  textAlign: TextAlign.end,
                  style: head ? style : style?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    final children = <Widget>[];
    if (header != null) children.add(row(header!.$1, header!.$2, head: true));
    for (final (a, b) in rows) {
      if (children.isNotEmpty) children.add(Divider(height: 1, color: divider));
      children.add(row(a, b));
    }
    return Column(children: children);
  }
}

/// Small banner above a list (offline, stale data).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.warning = false,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final bg = warning ? status.accent : theme.colorScheme.secondaryContainer;
    final fg = warning ? status.onAccent : theme.colorScheme.onSecondaryContainer;
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: fg))),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: fg),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
