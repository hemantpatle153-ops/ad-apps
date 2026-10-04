import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'main.dart' show appPackageName, privacyPolicyUrl;
import 'reminders.dart';
import 'store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final AppStore store;

  static const _goals = [1500, 2000, 2500, 3000, 3500, 4000];
  static const _glasses = [150, 200, 250, 300, 350, 500];
  static const _intervals = [60, 90, 120, 180];

  Future<void> _pickTime(BuildContext context, int current,
      void Function(int) set) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (t == null) return;
    set(t.hour * 60 + t.minute);
    await Reminders.instance.sync(store);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        bottomNavigationBar: const BannerAdSlot(),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Daily goal'),
              trailing: DropdownButton<int>(
                value: _goals.contains(store.goalMl) ? store.goalMl : 2000,
                items: [
                  for (final g in _goals)
                    DropdownMenuItem(value: g, child: Text('$g ml')),
                ],
                onChanged: (v) {
                  if (v != null) store.goalMl = v;
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.local_drink_outlined),
              title: const Text('Glass size'),
              trailing: DropdownButton<int>(
                value: _glasses.contains(store.glassMl) ? store.glassMl : 250,
                items: [
                  for (final g in _glasses)
                    DropdownMenuItem(value: g, child: Text('$g ml')),
                ],
                onChanged: (v) {
                  if (v != null) store.glassMl = v;
                },
              ),
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Water reminders'),
              value: store.waterReminders,
              onChanged: (v) async {
                store.waterReminders = v;
                if (v) await Reminders.instance.requestPermission();
                await Reminders.instance.sync(store);
              },
            ),
            ListTile(
              enabled: store.waterReminders,
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Wake up'),
              trailing: Text(formatMinutes(store.wakeMinutes)),
              onTap: () => _pickTime(
                  context, store.wakeMinutes, (v) => store.wakeMinutes = v),
            ),
            ListTile(
              enabled: store.waterReminders,
              leading: const Icon(Icons.bedtime_outlined),
              title: const Text('Bedtime'),
              trailing: Text(formatMinutes(store.sleepMinutes)),
              onTap: () => _pickTime(
                  context, store.sleepMinutes, (v) => store.sleepMinutes = v),
            ),
            ListTile(
              enabled: store.waterReminders,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Remind every'),
              trailing: DropdownButton<int>(
                value: _intervals.contains(store.intervalMinutes)
                    ? store.intervalMinutes
                    : 120,
                items: [
                  for (final m in _intervals)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m % 60 == 0 ? '${m ~/ 60} h' : '${m / 60} h'),
                    ),
                ],
                onChanged: store.waterReminders
                    ? (v) async {
                        if (v == null) return;
                        store.intervalMinutes = v;
                        await Reminders.instance.sync(store);
                      }
                    : null,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Rate this app'),
              onTap: () => openStorePage(appPackageName),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              onTap: () => openLink(privacyPolicyUrl),
            ),
            FutureBuilder<bool>(
              future: AdService.instance.privacyOptionsRequired(),
              builder: (context, snap) => snap.data == true
                  ? ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Ad privacy choices'),
                      onTap: AdService.instance.showPrivacyOptions,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
