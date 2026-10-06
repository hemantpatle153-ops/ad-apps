import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final Settings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _privacyOptions = false;

  @override
  void initState() {
    super.initState();
    AdService.instance.privacyOptionsRequired().then((v) {
      if (mounted) setState(() => _privacyOptions = v);
    }).catchError((_) {});
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(children: [
          _header('Look'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded),
                    label: Text('Dark')),
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded),
                    label: Text('Light')),
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.phone_android_rounded),
                    label: Text('System')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => s.setThemeMode(v.first),
            ),
          ),
          _header('Playback'),
          SwitchListTile(
            title: const Text('Resume where I stopped'),
            value: s.resume,
            onChanged: s.setResume,
          ),
          SwitchListTile(
            title: const Text('Keep my last playback speed'),
            value: s.rememberSpeed,
            onChanged: s.setRememberSpeed,
          ),
          ListTile(
            title: const Text('When I leave the app during a video'),
            subtitle: Text(switch (s.leaveAction) {
              LeaveAction.pause => 'Pause',
              LeaveAction.pip => 'Keep watching in a small window',
              LeaveAction.audio => 'Keep playing the sound',
            }),
            onTap: () async {
              final v = await showDialog<LeaveAction>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('When I leave the app'),
                  children: [
                    RadioGroup<LeaveAction>(
                      groupValue: s.leaveAction,
                      onChanged: (v) => Navigator.pop(ctx, v),
                      child: Column(children: [
                        for (final (a, label) in const [
                          (LeaveAction.pip, 'Keep watching in a small window'),
                          (LeaveAction.audio, 'Keep playing the sound'),
                          (LeaveAction.pause, 'Pause'),
                        ])
                          RadioListTile<LeaveAction>(value: a, title: Text(label)),
                      ]),
                    ),
                  ],
                ),
              );
              if (v != null) s.setLeaveAction(v);
            },
          ),
          _header('History'),
          ListTile(
            title: const Text('Clear recently played'),
            onTap: () {
              s.clearRecents();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recent list cleared')));
            },
          ),
          _header('About'),
          ListTile(
            title: const Text('Rate the app'),
            leading: const Icon(Icons.star_outline_rounded),
            onTap: () => openStorePage(packageName),
          ),
          ListTile(
            title: const Text('Privacy policy'),
            leading: const Icon(Icons.privacy_tip_outlined),
            onTap: () => openLink(privacyPolicyUrl),
          ),
          if (_privacyOptions)
            ListTile(
              title: const Text('Ad privacy choices'),
              leading: const Icon(Icons.tune_rounded),
              onTap: AdService.instance.showPrivacyOptions,
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
