import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Four-dot PIN entry with a big number pad.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onComplete,
    this.subtitle,
    this.length = 4,
  });

  final String title;
  final String? subtitle;
  final int length;

  /// Returns false to shake and clear (wrong PIN).
  final bool Function(String pin) onComplete;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  late final _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _press(String d) {
    if (_pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      final pin = _pin;
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        if (!widget.onComplete(pin)) {
          HapticFeedback.heavyImpact();
          _shake.forward(from: 0);
        }
        if (mounted) setState(() => _pin = '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {IconData? icon, VoidCallback? onTap}) => SizedBox(
          width: 76,
          height: 76,
          child: Material(
            color: icon == null ? scheme.surfaceContainerHigh : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap ?? () => _press(label),
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 26)
                    : Text(label,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_rounded, size: 40, color: scheme.primary),
        const SizedBox(height: 14),
        Text(widget.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 6),
          Text(widget.subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 24),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = t == 0 ? 0.0 : 12 * (1 - t) * ((t * 20).floor().isEven ? 1 : -1);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? scheme.primary : Colors.transparent,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in row)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: key(d)),
              ],
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 100),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: key('0')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: key('', icon: Icons.backspace_outlined, onTap: () {
                if (_pin.isNotEmpty) {
                  setState(() => _pin = _pin.substring(0, _pin.length - 1));
                }
              }),
            ),
          ],
        ),
      ],
    );
  }
}
