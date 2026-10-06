import 'package:flutter/material.dart';

import '../platform/native.dart';

/// Explains plainly what one phone can and can't do with Bluetooth, and
/// opens the right setting when the phone has a built-in way.
class BluetoothHelpScreen extends StatefulWidget {
  const BluetoothHelpScreen({super.key});

  @override
  State<BluetoothHelpScreen> createState() => _BluetoothHelpScreenState();
}

class _BluetoothHelpScreenState extends State<BluetoothHelpScreen> {
  ({bool leAudioBroadcast, String maker})? _features;

  @override
  void initState() {
    super.initState();
    Native.bluetoothFeatures().then((f) {
      if (mounted) setState(() => _features = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _features;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth speakers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Android plays Bluetooth music to one speaker at a time. No app '
            'can change that, but there are three ways around it:',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          const _Way(
            icon: Icons.phone_android,
            title: 'One phone per speaker (works everywhere)',
            body: 'Connect each Bluetooth speaker to a different phone. Host a '
                'party on one phone and join it from the others. Every speaker '
                'plays the same song in sync.',
            highlight: true,
          ),
          if (f != null && f.maker.contains('samsung'))
            const _Way(
              icon: Icons.speaker_group,
              title: 'Samsung Dual audio (your phone has it)',
              body: 'Connect two Bluetooth speakers. Pull down the quick panel, '
                  'tap Media output, and tick both speakers.',
            ),
          if (f != null && f.leAudioBroadcast)
            const _Way(
              icon: Icons.cell_tower,
              title: 'Audio sharing / Auracast (your phone has it)',
              body: 'Works with speakers and earbuds that support LE Audio or '
                  'show the Auracast logo. Open Bluetooth settings and look for '
                  'Audio sharing.',
            )
          else if (f != null)
            const _Way(
              icon: Icons.cell_tower,
              title: 'Audio sharing / Auracast',
              body: "Newer phones can broadcast to many LE Audio speakers at "
                  "once. This phone doesn't report support for it.",
            ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: Native.openBluetoothSettings,
            icon: const Icon(Icons.bluetooth),
            label: const Text('Open Bluetooth settings'),
          ),
        ],
      ),
    );
  }
}

class _Way extends StatelessWidget {
  const _Way({
    required this.icon,
    required this.title,
    required this.body,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: highlight ? scheme.primaryContainer : null,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(body),
        ),
        isThreeLine: true,
      ),
    );
  }
}
