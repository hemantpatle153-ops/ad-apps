import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../platform/native.dart';
import '../settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final Settings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.settings.name);
  String _deviceName = 'Phone';

  @override
  void initState() {
    super.initState();
    Native.deviceName().then((n) {
      if (mounted) setState(() => _deviceName = n);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Name other phones see',
                hintText: _deviceName,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => s.name = v,
            ),
          ),
          ListenableBuilder(
            listenable: s,
            builder: (context, _) => Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.speaker_phone),
                  title: const Text('Phone speaker delay'),
                  subtitle: Text('${s.delayMs(bluetooth: false)} ms'),
                ),
                ListTile(
                  leading: const Icon(Icons.bluetooth_audio),
                  title: const Text('Bluetooth speaker delay'),
                  subtitle: Text('${s.delayMs(bluetooth: true)} ms'),
                  trailing: TextButton(
                    onPressed: () => s.setDelayMs(Settings.defaultBluetoothDelayMs,
                        bluetooth: true),
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Change the delay with the slider during a party, '
                'by ear, while the music plays.'),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('Rate this app'),
            onTap: () => openStorePage(packageName),
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
                    leading: const Icon(Icons.ads_click),
                    title: const Text('Ad privacy choices'),
                    onTap: AdService.instance.showPrivacyOptions,
                  )
                : const SizedBox.shrink(),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Multi Speaker 1.0.0'),
            subtitle: Text('Music only travels on your own Wi-Fi or hotspot. '
                'Nothing is uploaded.'),
          ),
        ],
      ),
    );
  }
}
