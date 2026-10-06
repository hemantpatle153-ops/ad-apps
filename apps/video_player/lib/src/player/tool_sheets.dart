import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../settings.dart';
import 'effects.dart';
import 'play_item.dart';

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

String _hz(int f) => f >= 1000 ? '${f ~/ 1000}k' : '$f';

/// Ten-band equalizer with presets and night mode.
class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key, required this.settings, required this.fx});

  final Settings settings;
  final PlayerEffects fx;

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  late List<double> _gains = [...widget.settings.eqGains];
  late bool _night = widget.settings.nightMode;
  Timer? _debounce;

  void _apply() {
    widget.settings.setEq(_gains, night: _night);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120),
        () => widget.fx.applyAudio(widget.settings));
  }

  String? get _preset {
    for (final e in eqPresets.entries) {
      var same = true;
      for (var i = 0; i < _gains.length; i++) {
        if ((e.value[i] - _gains[i]).abs() > 0.05) same = false;
      }
      if (same) return e.key;
    }
    return null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetTitle('Equalizer',
              trailing: TextButton(
                  onPressed: () => setState(() {
                        _gains = List.filled(eqBands.length, 0);
                        _apply();
                      }),
                  child: const Text('Reset'))),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final name in eqPresets.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: _preset == name,
                      onSelected: (_) => setState(() {
                        _gains = [...eqPresets[name]!];
                        _apply();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: Row(children: [
              for (var i = 0; i < eqBands.length; i++)
                Expanded(
                  child: Column(children: [
                    Text('${_gains[i] > 0 ? '+' : ''}${_gains[i].round()}',
                        style: const TextStyle(fontSize: 11)),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: accent,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          ),
                          child: Slider(
                            min: -12,
                            max: 12,
                            value: _gains[i].clamp(-12, 12),
                            onChanged: (v) => setState(() {
                              _gains[i] = v;
                              _apply();
                            }),
                          ),
                        ),
                      ),
                    ),
                    Text(_hz(eqBands[i]), style: const TextStyle(fontSize: 11)),
                  ]),
                ),
            ]),
          ),
          SwitchListTile(
            title: const Text('Night mode'),
            subtitle: const Text('Quieter loud scenes, clearer dialogue'),
            value: _night,
            onChanged: (v) => setState(() {
              _night = v;
              _apply();
            }),
          ),
        ]),
      ),
    );
  }
}

/// Brightness, contrast, colour, rotation and mirror for this video.
class VideoAdjustSheet extends StatefulWidget {
  const VideoAdjustSheet({super.key, required this.fx});

  final PlayerEffects fx;

  @override
  State<VideoAdjustSheet> createState() => _VideoAdjustSheetState();
}

class _VideoAdjustSheetState extends State<VideoAdjustSheet> {
  VideoAdjust get a => widget.fx.adjust;

  Widget _slider(String label, int value, void Function(int) set) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          SizedBox(width: 92, child: Text(label)),
          Expanded(
            child: Slider(
              min: -100,
              max: 100,
              divisions: 40,
              value: value.toDouble(),
              onChanged: (v) {
                setState(() => set(v.round()));
                widget.fx.applyPicture();
              },
            ),
          ),
          SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.end)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetTitle('Picture',
              trailing: TextButton(
                onPressed: () {
                  setState(() {
                    a
                      ..brightness = 0
                      ..contrast = 0
                      ..saturation = 0
                      ..gamma = 0
                      ..hue = 0
                      ..rotate = 0
                      ..mirror = false;
                  });
                  widget.fx.applyPicture();
                },
                child: const Text('Reset'),
              )),
          _slider('Brightness', a.brightness, (v) => a.brightness = v),
          _slider('Contrast', a.contrast, (v) => a.contrast = v),
          _slider('Saturation', a.saturation, (v) => a.saturation = v),
          _slider('Gamma', a.gamma, (v) => a.gamma = v),
          _slider('Hue', a.hue, (v) => a.hue = v),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                avatar: const Icon(Icons.rotate_90_degrees_cw_rounded, size: 18),
                label: Text('Rotate ${a.rotate}°'),
                onPressed: () {
                  setState(() => a.rotate = (a.rotate + 90) % 360);
                  widget.fx.applyPicture();
                },
              ),
              FilterChip(
                avatar: const Icon(Icons.flip_rounded, size: 18),
                label: const Text('Mirror'),
                selected: a.mirror,
                onSelected: (v) {
                  setState(() => a.mirror = v);
                  widget.fx.applyPicture();
                },
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Pauses after a while or at the end of the video.
class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key, required this.active, required this.onPick});

  /// Current choice: null off, Duration.zero end of video.
  final Duration? active;
  final void Function(Duration? choice) onPick;

  @override
  Widget build(BuildContext context) {
    final options = <(String, Duration?)>[
      ('Off', null),
      ('End of this video', Duration.zero),
      for (final m in [10, 15, 30, 45, 60, 90, 120]) ('$m minutes', Duration(minutes: m)),
    ];
    return SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const SheetTitle('Sleep timer'),
        for (final (label, d) in options)
          ListTile(
            leading: Icon(active == d && (d != null || active == null)
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded),
            title: Text(label),
            onTap: () {
              onPick(d);
              Navigator.pop(context);
            },
          ),
      ]),
    );
  }
}

/// Saved moments in this video.
class BookmarksSheet extends StatefulWidget {
  const BookmarksSheet({
    super.key,
    required this.settings,
    required this.item,
    required this.position,
    required this.onJump,
  });

  final Settings settings;
  final PlayItem item;
  final Duration position;
  final void Function(Duration) onJump;

  @override
  State<BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<BookmarksSheet> {
  @override
  Widget build(BuildContext context) {
    final marks = widget.settings.bookmarksFor(widget.item.key);
    return SafeArea(
      child: ListView(shrinkWrap: true, children: [
        SheetTitle('Bookmarks',
            trailing: FilledButton.tonalIcon(
              onPressed: () => setState(
                  () => widget.settings.addBookmark(widget.item.key, widget.position)),
              icon: const Icon(Icons.bookmark_add_rounded),
              label: Text('Add ${formatDuration(widget.position)}'),
            )),
        if (marks.isEmpty)
          const ListTile(title: Text('No bookmarks yet')),
        for (final m in marks)
          ListTile(
            leading: const Icon(Icons.bookmark_rounded),
            title: Text(formatDuration(m)),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () =>
                  setState(() => widget.settings.removeBookmark(widget.item.key, m)),
            ),
            onTap: () {
              widget.onJump(m);
              Navigator.pop(context);
            },
          ),
      ]),
    );
  }
}

/// Chapters read from the file.
class ChaptersSheet extends StatelessWidget {
  const ChaptersSheet({super.key, required this.fx, required this.onJump});

  final PlayerEffects fx;
  final void Function(Duration) onJump;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<(String, Duration)>>(
        future: fx.chapters(),
        builder: (context, snap) {
          final list = snap.data;
          return ListView(shrinkWrap: true, children: [
            const SheetTitle('Chapters'),
            if (list == null)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
            else if (list.isEmpty)
              const ListTile(title: Text('This video has no chapters'))
            else
              for (final (title, at) in list)
                ListTile(
                  leading: const Icon(Icons.segment_rounded),
                  title: Text(title),
                  trailing: Text(formatDuration(at)),
                  onTap: () {
                    onJump(at);
                    Navigator.pop(context);
                  },
                ),
          ]);
        },
      ),
    );
  }
}

/// The videos lined up after this one.
class QueueSheet extends StatelessWidget {
  const QueueSheet({
    super.key,
    required this.queue,
    required this.index,
    required this.onPick,
  });

  final List<PlayItem> queue;
  final int index;
  final void Function(int) onPick;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetTitle('Playing queue  ·  ${index + 1} of ${queue.length}'),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: queue.length,
            controller: ScrollController(
                initialScrollOffset: (index * 56.0 - 112).clamp(0, double.infinity)),
            itemBuilder: (context, i) => ListTile(
              leading: i == index
                  ? Icon(Icons.equalizer_rounded, color: accent)
                  : Text('${i + 1}'),
              title: Text(queue[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: i == index ? TextStyle(color: accent, fontWeight: FontWeight.w600) : null),
              onTap: () {
                onPick(i);
                Navigator.pop(context);
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// Plus/minus row for a delay in seconds.
class DelayRow extends StatelessWidget {
  const DelayRow({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    void step(double d) => onChanged(((value + d) * 10).round() / 10);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: Text(label)),
        IconButton(onPressed: () => step(-0.1), icon: const Icon(Icons.remove_rounded)),
        GestureDetector(
          onTap: () => onChanged(0),
          child: SizedBox(
            width: 64,
            child: Text('${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} s',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ),
        IconButton(onPressed: () => step(0.1), icon: const Icon(Icons.add_rounded)),
      ]),
    );
  }
}
