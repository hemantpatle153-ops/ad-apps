import 'package:flutter/material.dart';

import '../settings.dart';
import '../speaker_delay.dart';
import '../sync/sync_controller.dart';

String formatTime(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// "This speaker plays late? Slide right." control for the output in use.
class DelayTile extends StatelessWidget {
  const DelayTile({super.key, required this.delay});

  final SpeakerDelay delay;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: delay,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(delay.output.bluetooth
                        ? Icons.bluetooth_audio
                        : Icons.speaker_phone),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(delay.outputLabel,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('${delay.ms} ms', style: theme.textTheme.titleSmall),
                  ],
                ),
                Slider(
                  value: delay.ms.toDouble(),
                  max: Settings.maxDelayMs.toDouble(),
                  divisions: Settings.maxDelayMs ~/ 10,
                  label: '${delay.ms} ms',
                  onChanged: (v) => delay.ms = v.round(),
                ),
                Text(
                  'Speaker delay. If this speaker sounds behind the others, '
                  'slide right. If it sounds ahead, slide left.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A small coloured chip that says how this phone is keeping up.
class SyncChip extends StatelessWidget {
  const SyncChip({super.key, required this.sync, this.downloadProgress});

  final SyncController sync;
  final double? downloadProgress;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([sync.phase, sync.errorMs]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final err = sync.errorMs.value;
        final (IconData icon, String text, Color color) = switch (sync.phase.value) {
          SyncPhase.idle => (Icons.hourglass_empty, 'Waiting for music', scheme.outline),
          SyncPhase.waitingForSong => (
              Icons.downloading,
              downloadProgress == null
                  ? 'Getting the song'
                  : 'Getting the song ${(downloadProgress! * 100).round()}%',
              scheme.tertiary
            ),
          SyncPhase.paused => (Icons.pause_circle_outline, 'Paused', scheme.outline),
          SyncPhase.starting => (Icons.sync, 'Starting in sync', scheme.tertiary),
          SyncPhase.pausedHere => (Icons.volume_off, 'Paused on this phone', scheme.error),
          SyncPhase.playing => (
              Icons.check_circle,
              err == null ? 'Playing in sync' : 'In sync (${err.abs()} ms)',
              err != null && err.abs() > 40 ? scheme.tertiary : Colors.green.shade600
            ),
        };
        return Chip(
          avatar: Icon(icon, color: color, size: 18),
          label: Text(text),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        );
      },
    );
  }
}

/// Animated sound waves around a speaker, shown while music plays.
class SpeakerPulse extends StatefulWidget {
  const SpeakerPulse({super.key, required this.playing, this.size = 72});

  final bool playing;
  final double size;

  @override
  State<SpeakerPulse> createState() => _SpeakerPulseState();
}

class _SpeakerPulseState extends State<SpeakerPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(SpeakerPulse old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.size;
    return SizedBox(
      width: s * 1.8,
      height: s * 1.8,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 2; i++)
              Builder(builder: (context) {
                final t = (_c.value + i / 2) % 1;
                return Container(
                  width: s * (1 + 0.8 * t),
                  height: s * (1 + 0.8 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.primary
                          .withValues(alpha: widget.playing ? (1 - t) * 0.6 : 0),
                      width: 3,
                    ),
                  ),
                );
              }),
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(Icons.speaker, color: scheme.onPrimary, size: s * 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks before ending a party, since leaving stops the music.
Future<bool> confirmLeave(BuildContext context,
    {required String title, required String body, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}
