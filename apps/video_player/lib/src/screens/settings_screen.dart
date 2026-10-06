import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../library/video_library.dart';
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

  void _hiddenFolders(Settings s) {
    final names = {for (final f in VideoLibrary.instance.folders) f.id: f.name};
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => ListView(shrinkWrap: true, children: [
            for (final id in s.hiddenFolders)
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: Text(names[id] ?? 'Folder'),
                trailing: TextButton(
                  onPressed: () => s.setFolderHidden(id, false),
                  child: const Text('Show'),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _editPartyName(Settings s) async {
    final c = TextEditingController(text: s.partyName);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(hintText: 'Shown to friends'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (v != null) s.setPartyName(v);
  }

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
                          RadioListTile<LeaveAction>(
                              value: a, title: Text(label)),
                      ]),
                    ),
                  ],
                ),
              );
              if (v != null) s.setLeaveAction(v);
            },
          ),
          ListTile(
            title: const Text('Double-tap to skip'),
            subtitle: Text('${s.doubleTapSeconds} seconds'),
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 5, label: Text('5')),
                ButtonSegment(value: 10, label: Text('10')),
                ButtonSegment(value: 30, label: Text('30')),
              ],
              selected: {s.doubleTapSeconds},
              onSelectionChanged: (v) => s.setDoubleTapSeconds(v.first),
            ),
          ),
          SwitchListTile(
            title: const Text('Hardware decoder'),
            subtitle: const Text(
                'Smoother and saves battery. Turn off if a video shows a green or black picture.'),
            value: s.hardwareDecoding,
            onChanged: s.setHardwareDecoding,
          ),
          _header('Library'),
          SwitchListTile(
            title: const Text('Show videos as a grid'),
            value: s.gridView,
            onChanged: s.setGridView,
          ),
          ListTile(
            title: const Text('Hidden folders'),
            subtitle: Text(s.hiddenFolders.isEmpty
                ? 'None. Long-press a folder to hide it.'
                : '${s.hiddenFolders.length} hidden'),
            enabled: s.hiddenFolders.isNotEmpty,
            onTap: () => _hiddenFolders(s),
          ),
          _header('Watch together'),
          ListTile(
            title: const Text('My name in watch parties'),
            subtitle:
                Text(s.partyName.isEmpty ? "This phone's name" : s.partyName),
            onTap: () => _editPartyName(s),
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

