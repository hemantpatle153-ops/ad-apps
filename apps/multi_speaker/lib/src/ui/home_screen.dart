import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../settings.dart';
import 'bluetooth_help_screen.dart';
import 'common.dart';
import 'host_screen.dart';
import 'join_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi Speaker'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => SettingsScreen(settings: settings))),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Center(child: SpeakerPulse(playing: true)),
                const SizedBox(height: 8),
                Text('One song. Every speaker.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Phones on the same Wi-Fi or hotspot play the same music '
                  'at the same moment, each on its own speaker.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _BigAction(
                  icon: Icons.queue_music,
                  title: 'Host a party',
                  subtitle: 'Play songs from this phone. Other phones join and play along.',
                  filled: true,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => HostScreen(settings: settings))),
                ),
                const SizedBox(height: 12),
                _BigAction(
                  icon: Icons.qr_code_scanner,
                  title: 'Join a party',
                  subtitle: "Play a friend's music on this phone and its speaker.",
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => JoinScreen(settings: settings))),
                ),
                const SizedBox(height: 20),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: const Text('Two Bluetooth speakers on one phone?'),
                    subtitle: const Text('See what your phone can do'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const BluetoothHelpScreen())),
                  ),
                ),
                const SizedBox(height: 12),
                const _HowItWorks(),
              ],
            ),
          ),
          const BannerAdSlot(),
        ],
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = filled ? scheme.onPrimary : scheme.onSecondaryContainer;
    return Material(
      color: filled ? scheme.primary : scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 40, color: fg),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: fg, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: fg)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.wifi, 'Put every phone on the same Wi-Fi, or on the host phone\'s hotspot.'),
      (Icons.library_music, 'On one phone tap Host a party and add songs.'),
      (Icons.qr_code, 'On the others tap Join a party and scan the code.'),
      (Icons.speaker_group, 'Connect each phone to its own speaker. Press play.'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How it works', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final (icon, text) in steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
