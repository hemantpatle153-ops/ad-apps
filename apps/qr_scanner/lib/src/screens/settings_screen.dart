import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../history_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('Rate this app'),
            onTap: () => openStorePage(appPackageName),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear scan history'),
            onTap: () async {
              await HistoryStore.instance.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('History cleared')),
                );
              }
            },
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
    );
  }
}
