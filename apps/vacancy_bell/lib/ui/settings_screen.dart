import 'package:flutter/material.dart';

import '../config.dart';
import '../core/json_read.dart';
import '../data/settings.dart';
import '../l10n/strings.dart';
import '../models/taxonomy.dart';
import 'disclaimer_screen.dart';
import 'permission.dart';
import 'scope.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.focusAlerts = false});

  /// Opened from "Job alerts": scroll to that section.
  final bool focusAlerts;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _permission;
  final _alertsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkPermission();
    if (widget.focusAlerts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _alertsKey.currentContext;
        if (c != null) Scrollable.ensureVisible(c);
      });
    }
  }

  Future<void> _checkPermission() async {
    try {
      final ok = await AppScope.read(context).services.notifications.permissionGranted();
      if (mounted) setState(() => _permission = ok);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final settings = app.settings;
    final prefs = settings.alertPrefs;
    final theme = Theme.of(context);
    final (hour, minute) = settings.reminderTime;
    Widget header(String t, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Semantics(
            header: true,
            child: Text(t,
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.t(L.settings))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          header(s.t(L.language)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AppLang>(
              segments: [
                for (final l in AppLang.values)
                  ButtonSegment(value: l, label: Text(s.languageName(l))),
              ],
              selected: {settings.lang},
              onSelectionChanged: (v) => settings.setLang(v.first),
            ),
          ),
          header(s.t(L.theme)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeChoice>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: ThemeChoice.system,
                    icon: const Icon(Icons.brightness_auto),
                    tooltip: s.t(L.themeSystem),
                    label: Text(s.t(L.themeSystem), overflow: TextOverflow.ellipsis)),
                ButtonSegment(
                    value: ThemeChoice.light,
                    icon: const Icon(Icons.light_mode_outlined),
                    tooltip: s.t(L.themeLight),
                    label: Text(s.t(L.themeLight), overflow: TextOverflow.ellipsis)),
                ButtonSegment(
                    value: ThemeChoice.dark,
                    icon: const Icon(Icons.dark_mode_outlined),
                    tooltip: s.t(L.themeDark),
                    label: Text(s.t(L.themeDark), overflow: TextOverflow.ellipsis)),
              ],
              selected: {settings.theme},
              onSelectionChanged: (v) => settings.setTheme(v.first),
            ),
          ),
          header(s.t(L.alerts), key: _alertsKey),
          if (_permission == false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(Icons.notifications_off_outlined,
                      color: theme.colorScheme.onErrorContainer),
                  title: Text(s.t(L.notificationsBlocked),
                      style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                  trailing: TextButton(
                    onPressed: () async {
                      await ensureNotificationPermission(context);
                      await _checkPermission();
                    },
                    child: Text(s.t(L.openSettings)),
                  ),
                ),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(s.t(L.alertsOn)),
            subtitle: Text(s.t(L.alertsOnHint)),
            value: prefs.enabled,
            onChanged: (v) async {
              if (v) await ensureNotificationPermission(context);
              await app.setAlertPrefs(prefs.copyWith(enabled: v));
              await _checkPermission();
            },
          ),
          if (prefs.enabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(s.t(L.alertTypes), style: theme.textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in PostType.values)
                  FilterChip(
                    label: Text(s.postType(t)),
                    selected: prefs.types.contains(t),
                    onSelected: (on) {
                      final set = {...prefs.types};
                      on ? set.add(t) : set.remove(t);
                      app.setAlertPrefs(prefs.copyWith(types: set));
                    },
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(s.t(L.alertCategories), style: theme.textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                FilterChip(
                  label: Text(s.t(L.allCategories)),
                  selected: prefs.categories.isEmpty,
                  onSelected: (_) => app.setAlertPrefs(prefs.copyWith(categories: {})),
                ),
                for (final c in JobCategory.values)
                  FilterChip(
                    label: Text(s.category(c)),
                    selected: prefs.categories.contains(c),
                    onSelected: (on) {
                      final set = {...prefs.categories};
                      on ? set.add(c) : set.remove(c);
                      app.setAlertPrefs(prefs.copyWith(categories: set));
                    },
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              secondary: const Icon(Icons.person_search_outlined),
              title: Text(s.t(L.alertMatchProfile)),
              subtitle: Text(s.t(L.alertMatchProfileHint)),
              value: prefs.matchProfile,
              onChanged: (v) => app.setAlertPrefs(prefs.copyWith(matchProfile: v)),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(s.t(L.reminderTime)),
            subtitle: Text('${s.time(hour, minute)} · ${s.t(L.reminderTimeHint)}'),
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: hour, minute: minute),
              );
              if (t != null) await app.setReminderTime(t.hour, t.minute);
            },
          ),
          header(s.t(L.about)),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(s.t(L.clearCache)),
            subtitle: Text(s.t(L.clearCacheHint)),
            onTap: () async {
              await app.clearCache();
              if (context.mounted) context.toast(s.t(L.cacheCleared));
            },
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: Text(s.t(L.disclaimer)),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const DisclaimerScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(s.t(L.privacyPolicy)),
            onTap: () => app.services.actions.openUrl(AppConfig.privacyPolicyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(s.t(L.about)),
            subtitle: Text(s.t(L.aboutText)),
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(s.t(L.appName)),
            subtitle: Text(s.t(L.version, {'v': appVersion})),
            onTap: () => app.services.actions.openUrl(AppConfig.playLink),
          ),
        ],
      ),
    );
  }
}

/// Shown in Settings; keep in step with pubspec.yaml.
const appVersion = '1.0.0';
