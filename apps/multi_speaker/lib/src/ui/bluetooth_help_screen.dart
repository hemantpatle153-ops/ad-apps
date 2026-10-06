import 'package:flutter/material.dart';

import '../platform/native.dart';
import 'widgets.dart';

/// "Many speakers from one phone": what this phone can do by itself, the
/// speakers' own party modes, and the one-phone-per-speaker way that works
/// everywhere. Android lets only the system stream to Bluetooth speakers,
/// one at a time, so no app can do it on its own.
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

  static const _brands = [
    ('JBL', 'PartyBoost (newer) or Connect+ (older)',
        'Turn on both speakers and press the PartyBoost button (the infinity sign) on each. The JBL Portable app can link up to 100.'),
    ('Sony', 'Party Connect or Stereo Pair',
        'In the Sony Music Center app, open the speaker and choose Party Connect (up to 100) or Stereo Pair (2).'),
    ('Ultimate Ears', 'PartyUp',
        'In the BOOM or MEGABOOM app, tap PartyUp and add more UE speakers.'),
    ('Bose', 'SimpleSync or Party mode',
        'In the Bose app (or Bose Connect), add a second speaker and choose Party mode.'),
    ('Anker Soundcore', 'PartyCast',
        'Press the PartyCast button on each speaker, or link them in the Soundcore app.'),
    ('Marshall', 'Stack mode',
        'In the Marshall Bluetooth app, open Stack mode and add the other speakers.'),
    ('boAt, Tribit, Zebronics and most budget speakers', 'TWS pairing (2 of the same model)',
        'Turn on two identical speakers, then double-press or hold the TWS or Play button on one. They pair as left and right.'),
  ];

  @override
  Widget build(BuildContext context) {
    final f = _features;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final samsung = f != null && f.maker.contains('samsung');
    return Scaffold(
      appBar: AppBar(title: const Text('Many speakers, one phone')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Android sends Bluetooth music to one speaker at a time, and no '
                "app can get around that. Here's what does work:",
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          const SectionHeader('On this phone'),
          if (f == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (f != null)
            _Way(
              icon: Icons.speaker_group,
              title: samsung ? 'Dual audio: your phone has it' : 'Dual audio (Samsung phones)',
              body: samsung
                  ? 'Plays to 2 Bluetooth speakers at once, each with its own volume. '
                      'Connect both speakers, open Media output and tick both.'
                  : "Samsung phones can play to 2 Bluetooth speakers at once. "
                      "This phone isn't a Samsung, so it doesn't have it.",
              good: samsung,
              action: samsung
                  ? FilledButton.tonal(
                      onPressed: Native.openMediaOutput,
                      child: const Text('Open Media output'))
                  : null,
            ),
          if (f != null)
            _Way(
              icon: Icons.cell_tower,
              title: f.leAudioBroadcast
                  ? 'Audio sharing (Auracast): your phone has it'
                  : 'Audio sharing (Auracast)',
              body: f.leAudioBroadcast
                  ? 'Shares to several LE Audio speakers and earbuds at once (look for '
                      'the Auracast logo). Find Audio sharing in Bluetooth settings.'
                  : "Newer phones can share to many LE Audio speakers at once. This "
                      "phone doesn't report support for it.",
              good: f.leAudioBroadcast,
              action: f.leAudioBroadcast
                  ? FilledButton.tonal(
                      onPressed: Native.openBluetoothSettings,
                      child: const Text('Bluetooth settings'))
                  : null,
            ),
          const SectionHeader("The speakers' own party mode"),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Many speakers link to each other. The phone connects to one, and '
              'every linked speaker plays. It usually needs speakers of the same brand.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (brand, feature, how) in _brands)
                  ExpansionTile(
                    title: Text(brand, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(feature),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedAlignment: Alignment.centerLeft,
                    children: [Text(how)],
                  ),
              ],
            ),
          ),
          const SectionHeader('Works with any speakers'),
          _Way(
            icon: Icons.phone_android,
            title: 'One phone per speaker (this app)',
            body: 'Connect each speaker to a phone (old phones work too), host a '
                'party on one, and join from the rest. Every speaker plays in sync, '
                'with its own volume on the host.',
            good: true,
            action: FilledButton(
                onPressed: () => Navigator.pop(context), child: const Text('Start a party')),
          ),
          const _Way(
            icon: Icons.settings_input_antenna,
            title: 'A Bluetooth transmitter',
            body: 'A small adapter that plugs into the phone (USB-C or headphone '
                'jack) and sends the sound to 2 speakers. Search for "dual link '
                'Bluetooth transmitter".',
            good: false,
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
    required this.good,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool good;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: good ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: good ? scheme.onPrimaryContainer : null),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(body),
                  if (action != null) ...[const SizedBox(height: 12), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
