import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../format.dart';
import '../library/subtitles.dart';
import '../settings.dart';
import 'effects.dart';
import 'tool_sheets.dart';

const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0];

const subtitleColors = [
  0xFFFFFFFF,
  0xFFFFEB3B,
  0xFF80DEEA,
  0xFFA5D6A7,
  0xFFFFAB91,
  0xFFF48FB1,
];

/// Bottom sheet that stays readable in landscape and on tablets.
Future<T?> showPlayerSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxWidth: 560,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    backgroundColor: const Color(0xFF16161D),
    builder: (context) => Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: Theme.of(context).colorScheme.copyWith(
              brightness: Brightness.dark,
              surface: const Color(0xFF16161D),
              onSurface: Colors.white,
            ),
      ),
      child: builder(context),
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      );
}

/// Playback speed from 0.25x to 4x: quick chips plus a fine slider.
class SpeedSheet extends StatefulWidget {
  const SpeedSheet({
    super.key,
    required this.player,
    required this.settings,
    required this.onRate,
  });

  final Player player;
  final Settings settings;

  /// Sets the speed (through the watch party when there is one).
  final void Function(double) onRate;

  @override
  State<SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<SpeedSheet> {
  late double _speed = widget.player.state.rate;

  void _set(double s) {
    s = (s * 20).round() / 20;
    setState(() => _speed = s);
    widget.onRate(s);
    widget.settings.setSpeed(s);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Title('Playback speed  ·  ${formatSpeed(_speed)}'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in speeds)
                    ChoiceChip(
                      label: Text(formatSpeed(s)),
                      selected: (_speed - s).abs() < 0.01,
                      onSelected: (_) => _set(s),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                    onPressed: () => _set((_speed - 0.05).clamp(0.25, 4.0)),
                    icon: const Icon(Icons.remove_rounded)),
                Expanded(
                  child: Slider(
                    min: 0.25,
                    max: 4,
                    divisions: 75,
                    value: _speed.clamp(0.25, 4.0),
                    label: formatSpeed(_speed),
                    onChanged: _set,
                  ),
                ),
                IconButton(
                    onPressed: () => _set((_speed + 0.05).clamp(0.25, 4.0)),
                    icon: const Icon(Icons.add_rounded)),
              ],
            ),
            SwitchListTile(
              title: const Text('Use this speed for every video'),
              value: widget.settings.rememberSpeed,
              onChanged: (v) => setState(() => widget.settings.setRememberSpeed(v)),
            ),
          ],
        ),
      ),
    );
  }
}

String _trackName(String id, String? title, String? language, int n) {
  final parts = [
    if (title != null && title.isNotEmpty) title,
    if (language != null && language.isNotEmpty) language.toUpperCase(),
  ];
  return parts.isEmpty ? 'Track $n' : parts.join(' · ');
}

/// Lists the audio tracks (languages) in the file.
class AudioTrackSheet extends StatefulWidget {
  const AudioTrackSheet({
    super.key,
    required this.player,
    required this.fx,
    required this.onEqualizer,
  });

  final Player player;
  final PlayerEffects fx;
  final VoidCallback onEqualizer;

  @override
  State<AudioTrackSheet> createState() => _AudioTrackSheetState();
}

class _AudioTrackSheetState extends State<AudioTrackSheet> {
  Player get player => widget.player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (context, snap) {
        final current = snap.data?.audio.id;
        final tracks = player.state.tracks.audio
            .where((t) => t.id != 'auto' && t.id != 'no')
            .toList();
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const _Title('Audio track'),
              if (tracks.isEmpty)
                const ListTile(title: Text('This video has one audio track')),
              for (final (i, t) in tracks.indexed)
                ListTile(
                  leading: Icon(t.id == current
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded),
                  title: Text(_trackName(t.id, t.title, t.language, i + 1)),
                  onTap: () {
                    player.setAudioTrack(t);
                    Navigator.pop(context);
                  },
                ),
              ListTile(
                leading: Icon(current == 'no'
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded),
                title: const Text('Mute (no audio)'),
                onTap: () {
                  player.setAudioTrack(AudioTrack.no());
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              DelayRow(
                label: 'Audio delay',
                value: widget.fx.audioDelay,
                onChanged: (v) => setState(() => widget.fx.setAudioDelay(v)),
              ),
              ListTile(
                leading: const Icon(Icons.graphic_eq_rounded),
                title: const Text('Equalizer and night mode'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onEqualizer();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Subtitle tracks, loading a file, and the text size and colour.
class SubtitleSheet extends StatefulWidget {
  const SubtitleSheet({
    super.key,
    required this.player,
    required this.settings,
    required this.fx,
  });

  final Player player;
  final Settings settings;
  final PlayerEffects fx;

  @override
  State<SubtitleSheet> createState() => _SubtitleSheetState();
}

class _SubtitleSheetState extends State<SubtitleSheet> {
  Player get player => widget.player;
  Settings get settings => widget.settings;

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose a subtitle file',
      type: FileType.any,
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;
    final ext = path.split('.').last.toLowerCase();
    if (!subtitleExtensions.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Choose a .srt, .ass, .ssa, .vtt or .sub file')));
      }
      return;
    }
    await player.setSubtitleTrack(
        SubtitleTrack.uri(path, title: files.first.name));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final current = player.state.track.subtitle.id;
    final tracks = player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    Widget radio(bool on) => Icon(
        on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('Subtitles'),
            ListTile(
              leading: radio(current == 'no'),
              title: const Text('Off'),
              onTap: () {
                player.setSubtitleTrack(SubtitleTrack.no());
                setState(() {});
              },
            ),
            for (final (i, t) in tracks.indexed)
              ListTile(
                leading: radio(t.id == current),
                title: Text(_trackName(t.id, t.title, t.language, i + 1)),
                onTap: () {
                  player.setSubtitleTrack(t);
                  setState(() {});
                },
              ),
            ListTile(
              leading: const Icon(Icons.file_open_rounded),
              title: const Text('Load subtitle file…'),
              subtitle: const Text('.srt, .ass, .vtt'),
              onTap: _pickFile,
            ),
            const Divider(),
            DelayRow(
              label: 'Subtitle delay',
              value: widget.fx.subtitleDelay,
              onChanged: (v) => setState(() => widget.fx.setSubtitleDelay(v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text('Text size  ·  ${settings.subtitleSize.round()}'),
            ),
            Slider(
              min: 12,
              max: 44,
              divisions: 32,
              value: settings.subtitleSize.clamp(12, 44),
              onChanged: (v) => setState(() => settings.setSubtitleStyle(size: v)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                children: [
                  for (final c in subtitleColors)
                    GestureDetector(
                      onTap: () =>
                          setState(() => settings.setSubtitleStyle(color: c)),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: settings.subtitleColor == c
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white24,
                            width: settings.subtitleColor == c ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text('Height above the bottom  ·  ${settings.subtitleLift.round()}'),
            ),
            Slider(
              max: 240,
              divisions: 24,
              value: settings.subtitleLift.clamp(0, 240),
              onChanged: (v) => setState(() => settings.setSubtitleStyle(lift: v)),
            ),
            SwitchListTile(
              title: const Text('Dark box behind text'),
              value: settings.subtitleBackground,
              onChanged: (v) =>
                  setState(() => settings.setSubtitleStyle(background: v)),
            ),
          ],
        ),
      ),
    );
  }
}
