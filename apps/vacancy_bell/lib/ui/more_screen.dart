import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n/strings.dart';
import 'age_calculator_screen.dart';
import 'disclaimer_screen.dart';
import 'profile_screen.dart';
import 'scope.dart';
import 'settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final profile = app.settings.profile;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget tile(IconData icon, String title, VoidCallback onTap, {String? subtitle}) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(
            header: true,
            child: Text(t,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.t(L.navMore))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          header(s.t(L.tools)),
          tile(Icons.badge_outlined, s.t(L.myDetails), () => push(const ProfileScreen()),
              subtitle: profile.qualification != null
                  ? s.qualification(profile.qualification!)
                  : s.t(L.eligNoProfile)),
          tile(Icons.calculate_outlined, s.t(L.ageCalculator),
              () => push(const AgeCalculatorScreen())),
          header(s.t(L.settings)),
          tile(Icons.notifications_outlined, s.t(L.alerts),
              () => push(const SettingsScreen(focusAlerts: true)),
              subtitle: s.t(app.settings.alertPrefs.enabled ? L.alertsOnHint : L.notSet)),
          tile(Icons.settings_outlined, s.t(L.settings), () => push(const SettingsScreen())),
          header(s.t(L.about)),
          tile(Icons.policy_outlined, s.t(L.disclaimer), () => push(const DisclaimerScreen())),
          tile(Icons.privacy_tip_outlined, s.t(L.privacyPolicy),
              () => app.services.actions.openUrl(AppConfig.privacyPolicyUrl)),
        ],
      ),
    );
  }
}
