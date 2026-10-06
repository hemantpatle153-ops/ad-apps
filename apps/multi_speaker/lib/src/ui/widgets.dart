import 'package:flutter/material.dart';

import '../settings.dart';
import '../sync/speaker.dart';

/// A square cover for a song: a gradient picked from the title, with its
/// first letter. Songs from files rarely carry artwork, and this looks
/// deliberate rather than empty.
class ArtworkTile extends StatelessWidget {
  const ArtworkTile({super.key, required this.title, this.size = 56, this.playing = false});

  final String? title;
  final double size;
  final bool playing;

  static const _palettes = [
    [Color(0xFF7B1FA2), Color(0xFFE91E63)],
    [Color(0xFF3949AB), Color(0xFF00ACC1)],
    [Color(0xFFF4511E), Color(0xFFFFB300)],
    [Color(0xFF00897B), Color(0xFF7CB342)],
    [Color(0xFF5E35B1), Color(0xFF1E88E5)],
    [Color(0xFFD81B60), Color(0xFFFF7043)],
  ];

  @override
  Widget build(BuildContext context) {
    final t = title?.trim() ?? '';
    final colors = _palettes[t.hashCode.abs() % _palettes.length];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
            colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          if (playing && size > 80)
            BoxShadow(
                color: colors.last.withValues(alpha: 0.45),
                blurRadius: size * 0.25,
                offset: Offset(0, size * 0.06)),
        ],
      ),
      alignment: Alignment.center,
      child: t.isEmpty
          ? Icon(Icons.music_note, color: Colors.white, size: size * 0.5)
          : Text(t.characters.first.toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w700)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One speaker in the party: its name and output, how well it is in sync,
/// its own volume and mute, and (folded away) its sync delay.
class SpeakerCard extends StatefulWidget {
  const SpeakerCard({
    super.key,
    required this.name,
    required this.output,
    required this.bluetooth,
    required this.level,
    required this.onLevel,
    required this.delayMs,
    required this.onDelay,
    this.status,
    this.statusColor,
    this.isThisPhone = false,
    this.onRemove,
    this.footer,
  });

  final String name;
  final String output;
  final bool bluetooth;
  final SpeakerLevel level;
  final ValueChanged<SpeakerLevel> onLevel;
  final int delayMs;
  final ValueChanged<int> onDelay;
  final String? status;
  final Color? statusColor;
  final bool isThisPhone;
  final VoidCallback? onRemove;
  final Widget? footer;

  @override
  State<SpeakerCard> createState() => _SpeakerCardState();
}

class _SpeakerCardState extends State<SpeakerCard> {
  bool _showDelay = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = widget;
    final muted = w.level.muted;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: w.bluetooth ? scheme.primaryContainer : scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    w.bluetooth ? Icons.bluetooth_audio : Icons.speaker,
                    color: w.bluetooth ? scheme.onPrimaryContainer : scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(w.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          if (w.isThisPhone) ...[
                            const SizedBox(width: 6),
                            _Tag('This phone', color: scheme.primary),
                          ],
                        ],
                      ),
                      Text(w.output,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (w.status != null)
                  _Tag(w.status!, color: w.statusColor ?? scheme.outline),
                if (w.onRemove != null)
                  PopupMenuButton<void>(
                    tooltip: 'More',
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        onTap: w.onRemove,
                        child: const ListTile(
                          leading: Icon(Icons.person_remove_outlined),
                          title: Text('Remove from party'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton(
                  tooltip: muted ? 'Unmute' : 'Mute',
                  onPressed: () => w.onLevel(w.level.copyWith(muted: !muted)),
                  icon: Icon(
                    muted
                        ? Icons.volume_off
                        : w.level.volume < 0.5
                            ? Icons.volume_down
                            : Icons.volume_up,
                    color: muted ? scheme.error : null,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: w.level.volume,
                    onChanged: (v) => w.onLevel(w.level.copyWith(volume: v, muted: false)),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(muted ? 'Muted' : '${(w.level.volume * 100).round()}%',
                      textAlign: TextAlign.end, style: theme.textTheme.labelMedium),
                ),
                IconButton(
                  tooltip: 'Sync delay',
                  onPressed: () => setState(() => _showDelay = !_showDelay),
                  icon: Icon(Icons.tune, color: _showDelay ? scheme.primary : null),
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState:
                  _showDelay ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Sync delay', style: theme.textTheme.labelLarge),
                        const Spacer(),
                        Text('${w.delayMs} ms', style: theme.textTheme.labelLarge),
                      ],
                    ),
                    Slider(
                      value: w.delayMs.clamp(0, Settings.maxDelayMs).toDouble(),
                      max: Settings.maxDelayMs.toDouble(),
                      divisions: Settings.maxDelayMs ~/ 10,
                      label: '${w.delayMs} ms',
                      onChanged: (v) => w.onDelay(v.round()),
                    ),
                    Text(
                      'If this speaker sounds behind the others, slide right. '
                      'If it sounds ahead, slide left.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            ?w.footer,
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
