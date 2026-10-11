import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'scope.dart';
import 'theme.dart';

/// Public sources the feed is built from. Listed in the app and on the
/// Play listing as required by Google Play's government information policy.
const officialSources = <(String, String)>[
  ('Staff Selection Commission', 'https://ssc.gov.in'),
  ('Union Public Service Commission', 'https://upsc.gov.in'),
  ('Indian Railways', 'https://indianrailways.gov.in'),
  ('Railway Recruitment Boards', 'https://www.rrbcdg.gov.in'),
  ('Institute of Banking Personnel Selection', 'https://www.ibps.in'),
  ('National Testing Agency', 'https://nta.ac.in'),
  ('Employment News', 'https://www.employmentnews.gov.in'),
];

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    Widget para(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s.t(L.disclaimer))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            color: status.accent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, color: status.onAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.t(L.disclaimerNotAffiliated),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: status.onAccent, fontWeight: FontWeight.w600, height: 1.5)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          para(s.t(L.disclaimerHow)),
          para(s.t(L.disclaimerVerify)),
          para(s.t(L.disclaimerNoFees)),
          para(s.t(L.disclaimerReport)),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(s.t(L.sourcesTitle),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final (name, url) in officialSources)
                ListTile(
                  leading: const Icon(Icons.public),
                  title: Text(name),
                  subtitle: Text(Uri.parse(url).host),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => app.services.actions.openUrl(url),
                ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(s.t(L.sourceStatePsc)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
