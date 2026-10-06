import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../player/tool_sheets.dart';
import 'party.dart';
import 'protocol.dart';

const partyEmojis = ['😂', '😍', '😮', '😢', '👏', '🔥', '❤️', '👍'];

/// Who is watching, the join QR code (host), chat and reactions.
class PartySheet extends StatefulWidget {
  const PartySheet({super.key, required this.party});

  final WatchParty party;

  @override
  State<PartySheet> createState() => _PartySheetState();
}

class _PartySheetState extends State<PartySheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    widget.party.sendChat(_text.text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.party,
      builder: (context, _) {
        final p = widget.party;
        final host = p is PartyHost ? p : null;
        final chat = p.messages.where((m) => !m.emoji).toList().reversed.toList();
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SheetTitle('Watch with friends  ·  ${p.members.length} watching'),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  if (host != null) _JoinCard(host: host),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final m in p.members)
                        Chip(
                          avatar: CircleAvatar(
                            backgroundColor: scheme.primary,
                            child: Text(m.isEmpty ? '?' : m.characters.first.toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                          label: Text(m == p.myName ? '$m (you)' : m),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (final e in partyEmojis)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => p.sendReaction(e),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(e, style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final m in chat.take(40))
                    ListTile(
                      dense: true,
                      title: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: '${m.from}  ',
                            style: TextStyle(
                                color: scheme.primary, fontWeight: FontWeight.w600)),
                        TextSpan(text: m.text),
                      ])),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Say something',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.host});

  final PartyHost host;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (host.addresses.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.wifi_off_rounded),
        title: const Text('Connect to Wi-Fi or turn on your hotspot'),
        subtitle: const Text('Friends join over the same Wi-Fi or your hotspot'),
        trailing: TextButton(onPressed: host.refreshAddresses, child: const Text('Retry')),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: QrImageView(
            data: host.joinCode.encode(),
            size: 132,
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Friends join from Video Player',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'On the same Wi-Fi or your hotspot: Watch together, then scan '
              'this code or tap your name.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 6),
            SelectableText('${host.addresses.first}:${host.port}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

/// Emoji reactions that float up the right edge, and chat lines that fade
/// in at the left, drawn over the video.
class PartyOverlay extends StatefulWidget {
  const PartyOverlay({super.key, required this.party, required this.bottom});

  final WatchParty party;
  final double bottom;

  @override
  State<PartyOverlay> createState() => _PartyOverlayState();
}

class _Floating {
  _Floating(this.emoji, this.x);
  final String emoji;
  final double x;
  final key = UniqueKey();
}

class _PartyOverlayState extends State<PartyOverlay> {
  final _floating = <_Floating>[];
  final _lines = <PartyMessage>[];
  final _rng = Random();
  StreamSubscription<PartyMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.party.incoming.listen(_onMessage);
  }

  void _onMessage(PartyMessage m) {
    if (!mounted) return;
    if (m.emoji) {
      final f = _Floating(m.text, _rng.nextDouble());
      setState(() => _floating.add(f));
      Timer(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _floating.remove(f));
      });
    } else {
      setState(() {
        _lines.add(m);
        if (_lines.length > 3) _lines.removeAt(0);
      });
      Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _lines.remove(m));
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(children: [
        for (final f in _floating)
          Positioned(
            key: f.key,
            right: 24 + f.x * 60,
            bottom: widget.bottom,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 2500),
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(
                opacity: (1 - t).clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(sin(t * 6 + f.x * 3) * 12, -t * 260),
                  child: Transform.scale(scale: 0.8 + t * 0.6, child: child),
                ),
              ),
              child: Text(f.emoji, style: const TextStyle(fontSize: 34)),
            ),
          ),
        Positioned(
          left: 16,
          bottom: widget.bottom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final m in _lines)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${m.from}  ',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700)),
                    TextSpan(text: m.text, style: const TextStyle(color: Colors.white)),
                  ])),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
