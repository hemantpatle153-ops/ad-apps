import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../core/bi.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import '../data/user_store.dart';
import '../l10n/strings.dart';
import 'info_screen.dart';
import 'permissions.dart';
import 'scope.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _notificationsOn;
  bool _privacyOptions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPermission());
    if (AppConfig.adsEnabled) {
      AdService.instance.privacyOptionsRequired().then((v) {
        if (mounted) setState(() => _privacyOptions = v);
      });
    }
  }

  Future<void> _refreshPermission() async {
    final on = await AppScope.read(context).reminders.enabled();
    if (mounted) setState(() => _notificationsOn = on);
  }

  Future<void> _pickTime() async {
    final app = AppScope.read(context);
    final m = app.settings.reminderMinutes;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    await app.updateSettings((s) => s.reminderMinutes = t.hour * 60 + t.minute,
        reschedule: true);
  }

  Future<void> _toggleReminder(bool daily, bool on) async {
    final app = AppScope.read(context);
    if (on) {
      final granted = await ensureNotifications(context);
      if (mounted) setState(() => _notificationsOn = granted);
    }
    await app.updateSettings(
        (s) => daily ? s.dailyReminder = on : s.streakReminder = on,
        reschedule: true);
  }

  Future<void> _pickExams() async {
    final app = AppScope.read(context);
    final s = app.s;
    final chosen = {...app.settings.targetExams};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(s.t(T.targetExams)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in kExams)
                CheckboxListTile(
                  value: chosen.contains(e),
                  title: Text(s.exam(e)),
                  onChanged: (v) => setLocal(() => v == true ? chosen.add(e) : chosen.remove(e)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t(T.cancel))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t(T.ok))),
          ],
        ),
      ),
    );
    if (ok == true) {
      await app.updateSettings(
          (st) => st.targetExams = [for (final e in kExams) if (chosen.contains(e)) e]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    final st = app.settings;
    final remindersWanted = st.dailyReminder || st.streakReminder;
    return Scaffold(
      appBar: AppBar(title: Text(s.t(T.settingsTitle))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(s.t(T.language)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<Lang>(
              segments: const [
                ButtonSegment(value: Lang.en, label: Text('English')),
                ButtonSegment(value: Lang.hi, label: Text('हिंदी')),
              ],
              selected: {st.lang},
              onSelectionChanged: (v) =>
                  app.updateSettings((x) => x.lang = v.first, reschedule: true),
            ),
          ),
          _Header(s.t(T.theme)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AppTheme>(
              segments: [
                ButtonSegment(value: AppTheme.system, label: Text(s.t(T.themeSystem))),
                ButtonSegment(value: AppTheme.light, label: Text(s.t(T.themeLight))),
                ButtonSegment(value: AppTheme.dark, label: Text(s.t(T.themeDark))),
              ],
              selected: {st.theme},
              onSelectionChanged: (v) => app.updateSettings((x) => x.theme = v.first),
            ),
          ),
          _Header(s.t(T.timer)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in kTimerChoices)
                ChoiceChip(
                  label: Text(t == 0 ? s.t(T.timerOff) : '${t}s'),
                  selected: st.timerSeconds == t,
                  onSelected: (_) => app.updateSettings((x) => x.timerSeconds = t),
                ),
            ]),
          ),
          if (st.timerSeconds > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(s.f(T.timerSeconds, {'n': st.timerSeconds}),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: Text(s.t(T.sound)),
            value: st.sound,
            onChanged: (v) => app.updateSettings((x) => x.sound = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: Text(s.t(T.haptics)),
            value: st.haptics,
            onChanged: (v) => app.updateSettings((x) => x.haptics = v),
          ),
          _Header(s.t(T.reminders)),
          if (remindersWanted && _notificationsOn == false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: Text(s.t(T.notificationsBlocked)),
                  onTap: () async {
                    final ok = await ensureNotifications(context);
                    if (mounted) setState(() => _notificationsOn = ok);
                  },
                ),
              ),
            ),
          SwitchListTile(
            key: const ValueKey('dailyReminder'),
            secondary: const Icon(Icons.alarm),
            title: Text(s.t(T.dailyReminder)),
            value: st.dailyReminder,
            onChanged: (v) => _toggleReminder(true, v),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(s.t(T.reminderTime)),
            subtitle: Text('${formatMinutes(st.reminderMinutes)} IST'),
            enabled: st.dailyReminder,
            onTap: _pickTime,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.local_fire_department_outlined),
            title: Text(s.t(T.streakReminder)),
            subtitle: Text(s.t(T.streakReminderSub)),
            value: st.streakReminder,
            onChanged: (v) => _toggleReminder(false, v),
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: Text(s.t(T.targetExams)),
            subtitle: Text(st.targetExams.isEmpty
                ? s.t(T.targetExamsNone)
                : st.targetExams.map(s.exam).join(', ')),
            onTap: _pickExams,
          ),
          _Header(s.t(T.data)),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(s.t(T.clearCache)),
            subtitle: Text(s.t(T.clearCacheSub)),
            onTap: () async {
              await app.clearCache();
              if (context.mounted) showSnack(context, s.t(T.clearCacheDone));
            },
          ),
          ListTile(
            leading: const Icon(Icons.update),
            title: Text(app.lastUpdated == null
                ? s.t(T.neverUpdated)
                : s.f(T.updatedAt, {'when': s.ago(app.lastUpdated!, app.now())})),
          ),
          _Header(s.t(T.about)),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(s.t(T.about)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InfoScreen(title: s.t(T.about), body: [s.t(T.aboutBody)]))),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(s.t(T.sourcesDisclaimer)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InfoScreen(
                    title: s.t(T.sourcesDisclaimer),
                    body: [s.t(T.sourcesBody), s.t(T.disclaimerBody)]))),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(s.t(T.privacyPolicy)),
            onTap: () => openLink(AppConfig.privacyPolicyUrl),
          ),
          if (_privacyOptions)
            ListTile(
              leading: const Icon(Icons.ads_click),
              title: Text(s.t(T.adPrivacy)),
              onTap: AdService.instance.showPrivacyOptions,
            ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(s.t(T.rateApp)),
            onTap: () => openStorePage(AppConfig.packageName),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: Text(s.f(T.version, {'v': AppConfig.appVersion})),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SectionTitle(text),
      );
}
