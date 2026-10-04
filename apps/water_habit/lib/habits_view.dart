import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'reminders.dart';
import 'store.dart';

class HabitsView extends StatelessWidget {
  const HabitsView({super.key, required this.store});
  final AppStore store;

  Future<void> _edit(BuildContext context, [Habit? habit]) async {
    final name = TextEditingController(text: habit?.name ?? '');
    int? reminder = habit?.reminderMinutes;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(habit == null ? 'New habit' : 'Edit habit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Habit', hintText: 'Read 10 pages'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Daily reminder'),
                subtitle: reminder == null
                    ? null
                    : Text(formatMinutes(reminder!)),
                value: reminder != null,
                onChanged: (on) async {
                  if (!on) return setState(() => reminder = null);
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: const TimeOfDay(hour: 20, minute: 0),
                  );
                  if (t != null) {
                    setState(() => reminder = t.hour * 60 + t.minute);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final text = name.text.trim();
    name.dispose();
    if (ok != true || text.isEmpty) return;
    if (habit == null) {
      await store.addHabit(text, reminder);
    } else {
      habit
        ..name = text
        ..reminderMinutes = reminder;
      await store.saveHabits();
    }
    if (reminder != null) await Reminders.instance.requestPermission();
    await Reminders.instance.sync(store);
    // Natural break: the habit form is finished.
    if (habit == null) AdService.instance.maybeShowInterstitial();
  }

  Future<void> _remove(BuildContext context, Habit h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${h.name}"?'),
        content: const Text('Its history and reminder will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await store.removeHabit(h);
    await Reminders.instance.sync(store);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final week = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final dayNames = MaterialLocalizations.of(context).narrowWeekdays;
    return Stack(
      children: [
        if (store.habits.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No habits yet. Add one, like a walk, reading or stretching, and tick it off each day to build a streak.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
            itemCount: store.habits.length,
            itemBuilder: (_, i) {
              final h = store.habits[i];
              final streak = h.streak(today);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Checkbox(
                          value: h.doneOn(today),
                          onChanged: (_) => store.toggleHabit(h, today),
                        ),
                        title: Text(h.name),
                        subtitle: Text([
                          '$streak day streak',
                          if (h.reminderMinutes != null)
                            'reminder ${formatMinutes(h.reminderMinutes!)}',
                        ].join(' · ')),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) => v == 'edit'
                              ? _edit(context, h)
                              : _remove(context, h),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final d in week)
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => store.toggleHabit(h, d),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Column(
                                  children: [
                                    Text(dayNames[d.weekday % 7],
                                        style: theme.textTheme.labelSmall),
                                    Icon(
                                      h.doneOn(d)
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 22,
                                      color: h.doneOn(d)
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outline,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add),
            label: const Text('Add habit'),
          ),
        ),
      ],
    );
  }
}
