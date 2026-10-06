import 'package:flutter/material.dart';

/// The pill in the middle of the screen for brightness, volume, seek, zoom.
class GestureIndicator extends StatelessWidget {
  const GestureIndicator({
    super.key,
    required this.icon,
    required this.text,
    this.level,
    this.subtext,
  });

  final IconData icon;
  final String text;
  final String? subtext;

  /// 0..1 fill for brightness and volume.
  final double? level;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
          if (subtext != null) ...[
            const SizedBox(height: 4),
            Text(subtext!,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
          if (level != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: level!.clamp(0.0, 1.0),
                  minHeight: 5,
                  color: accent,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Half-moon ripple on the left or right edge after a double tap.
class DoubleTapRipple extends StatelessWidget {
  const DoubleTapRipple({super.key, required this.forward, required this.seconds});

  final bool forward;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth * 0.36;
      return Align(
        alignment: forward ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: w,
          height: c.maxHeight,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: forward
                ? BorderRadius.horizontal(left: Radius.circular(c.maxHeight))
                : BorderRadius.horizontal(right: Radius.circular(c.maxHeight)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                  color: Colors.white, size: 36),
              const SizedBox(height: 4),
              Text('${forward ? '+' : '-'}$seconds s',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    });
  }
}

/// Subtitles drawn by the app so size and colour can change, and so pinch
/// zoom doesn't push them off screen.
class SubtitleText extends StatelessWidget {
  const SubtitleText({
    super.key,
    required this.lines,
    required this.size,
    required this.color,
    required this.background,
  });

  final List<String> lines;
  final double size;
  final Color color;
  final bool background;

  @override
  Widget build(BuildContext context) {
    final text = lines.where((l) => l.trim().isNotEmpty).join('\n');
    if (text.isEmpty) return const SizedBox.shrink();
    const outline = [
      Shadow(blurRadius: 3, color: Colors.black),
      Shadow(offset: Offset(1.5, 1.5), blurRadius: 2, color: Colors.black),
      Shadow(offset: Offset(-1.5, -1.5), blurRadius: 2, color: Colors.black),
    ];
    return Container(
      padding: background
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
          : EdgeInsets.zero,
      decoration: background
          ? BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6))
          : null,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          color: color,
          height: 1.25,
          fontWeight: FontWeight.w500,
          shadows: background ? null : outline,
        ),
      ),
    );
  }
}
