import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../logic/job_query.dart';
import '../models/taxonomy.dart';
import 'scope.dart';

Future<void> showFilterSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AppScope(controller: AppScope.read(context), child: const FilterSheet()),
    );

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late JobQuery _q = AppScope.read(context).query;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    final canEligible = app.settings.profile.canCheckEligibility;
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Semantics(
            header: true,
            child: Text(t, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
        );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(s.t(L.filters),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () => setState(() => _q = _q.cleared()),
                  child: Text(s.t(L.clearAll)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                heading(s.t(L.sortBy)),
                SegmentedButton<SortOrder>(
                  segments: [
                    ButtonSegment(
                        value: SortOrder.newest,
                        label: Text(s.t(L.sortNewest)),
                        icon: const Icon(Icons.schedule)),
                    ButtonSegment(
                        value: SortOrder.closingSoon,
                        label: Text(s.t(L.sortClosing)),
                        icon: const Icon(Icons.hourglass_bottom)),
                  ],
                  selected: {_q.sort},
                  onSelectionChanged: (v) => setState(() => _q = _q.copyWith(sort: v.first)),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t(L.onlyEligible)),
                  subtitle: Text(s.t(canEligible ? L.onlyEligibleHint : L.onlyEligibleNeedsProfile)),
                  value: _q.onlyEligible && canEligible,
                  onChanged: canEligible
                      ? (v) => setState(() => _q = _q.copyWith(onlyEligible: v))
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t(L.hideClosed)),
                  value: _q.hideClosed,
                  onChanged: (v) => setState(() => _q = _q.copyWith(hideClosed: v)),
                ),
                heading(s.t(L.filterCategory)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in JobCategory.values)
                      FilterChip(
                        label: Text(s.category(c)),
                        selected: _q.categories.contains(c),
                        onSelected: (on) => setState(() {
                          final set = {..._q.categories};
                          on ? set.add(c) : set.remove(c);
                          _q = _q.copyWith(categories: set);
                        }),
                      ),
                  ],
                ),
                heading(s.t(L.filterQualification)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in Qualification.userLevels)
                      FilterChip(
                        label: Text(s.qualification(q)),
                        selected: _q.qualifications.contains(q),
                        onSelected: (on) => setState(() {
                          final set = {..._q.qualifications};
                          on ? set.add(q) : set.remove(q);
                          _q = _q.copyWith(qualifications: set);
                        }),
                      ),
                  ],
                ),
                heading(s.t(L.filterState)),
                DropdownButtonFormField<String?>(
                  initialValue: _q.state,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: null, child: Text(s.t(L.allStates))),
                    for (final st in indianStates)
                      DropdownMenuItem(value: st.code, child: Text(st.name(s.lang))),
                  ],
                  onChanged: (v) => setState(() => _q = _q.copyWith(state: () => v)),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    app.setQuery(_q.copyWith(text: app.query.text));
                    Navigator.of(context).pop();
                  },
                  child: Text(s.t(L.showResults)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
