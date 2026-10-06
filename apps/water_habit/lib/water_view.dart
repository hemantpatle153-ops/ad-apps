import 'dart:math';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'store.dart';

class WaterView extends StatelessWidget {
  const WaterView({super.key, required this.store});
  final AppStore store;

  Future<void> _add(BuildContext context, int ml) async {
    final before = store.todayMl;
    await store.addWater(ml);
    if (before < store.goalMl && store.todayMl >= store.goalMl &&
        context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.emoji_events, size: 40),
          title: const Text('Goal reached!'),
          content: Text(
              'You drank ${store.todayMl} ml today. Streak: ${store.waterStreak()} days.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c), child: const Text('Nice')),
          ],
        ),
      );
      // Natural break: the daily goal was just completed.
      AdService.instance.maybeShowInterstitial();
    }
  }

  Future<void> _custom(BuildContext context) async {
    final c = TextEditingController();
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add amount'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'ml'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    // Not disposed here: the dialog's TextField is still rebuilt during the
    // closing animation, and a disposed controller would throw. It is
    // garbage collected with the dialog.
    if (v != null && v > 0 && v <= 5000 && context.mounted) _add(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ml = store.todayMl;
    final goal = store.goalMl;
    final glass = store.glassMl;
    final now = DateTime.now();
    final week = [
      for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i)),
    ];
    final weekMax =
        max(goal, week.map(store.mlOn).fold<int>(0, max)).toDouble();
    final dayNames = MaterialLocalizations.of(context).narrowWeekdays;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: (ml / goal).clamp(0, 1).toDouble(),
                  strokeWidth: 16,
                  strokeCap: StrokeCap.round,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.water_drop,
                          size: 36, color: theme.colorScheme.primary),
                      Text('$ml ml', style: theme.textTheme.headlineMedium),
                      Text('of $goal ml'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(ml >= goal
              ? 'Goal reached. Streak: ${store.waterStreak()} days'
              : '${goal - ml} ml to go. Streak: ${store.waterStreak()} days'),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _add(context, glass),
              icon: const Icon(Icons.local_drink),
              label: Text('+$glass ml'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _add(context, glass * 2),
              icon: const Icon(Icons.local_drink),
              label: Text('+${glass * 2} ml'),
            ),
            OutlinedButton.icon(
              onPressed: () => _custom(context),
              icon: const Icon(Icons.edit),
              label: const Text('Custom'),
            ),
            if (store.todayDrinks.isNotEmpty)
              TextButton.icon(
                onPressed: store.undoWater,
                icon: const Icon(Icons.undo),
                label: Text('Undo ${store.todayDrinks.last} ml'),
              ),
          ],
        ),
        const SizedBox(height: 32),
        Text('Last 7 days', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in week)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${(store.mlOn(d) / 1000).toStringAsFixed(1)}L',
                            style: theme.textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Container(
                          height: 100 * store.mlOn(d) / weekMax,
                          decoration: BoxDecoration(
                            color: store.mlOn(d) >= goal
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary
                                    .withValues(alpha: .4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(dayNames[d.weekday % 7]),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
