import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../player/play_item.dart';
import '../player/player_screen.dart';
import '../player/system_channel.dart';
import '../settings.dart';
import 'discovery.dart';
import 'online.dart';
import 'party.dart';
import 'party_widgets.dart';
import 'pick_video_screen.dart';
import 'protocol.dart';

/// Joins a friend's watch party: scan their QR code, tap one found on this
/// Wi-Fi, or type the address shown on their phone.
class JoinPartyScreen extends StatefulWidget {
  const JoinPartyScreen({super.key, required this.settings});

  final Settings settings;

  @override
  State<JoinPartyScreen> createState() => _JoinPartyScreenState();
}

class _JoinPartyScreenState extends State<JoinPartyScreen> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _address = TextEditingController();
  final _code = TextEditingController();
  BeaconListener? _listener;
  StreamSubscription<List<FoundHost>>? _sub;
  List<FoundHost> _found = [];
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  Future<void> _listen() async {
    await SystemChannel.instance.holdNetwork(true);
    final l = await BeaconListener.start();
    if (!mounted) {
      l?.stop();
      return;
    }
    _listener = l;
    _sub = l?.hosts.listen((h) => setState(() => _found = h));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _listener?.stop();
    _scanner.dispose();
    _address.dispose();
    _code.dispose();
    if (!_joining) SystemChannel.instance.holdNetwork(false);
    super.dispose();
  }

  Future<void> _join(JoinCode code) async {
    if (_joining) return;
    setState(() => _joining = true);
    await _scanner.stop();
    final s = widget.settings;
    final guest = PartyGuest(await _myName(), code);
    final ok = await guest.connect();
    if (!mounted) {
      guest.close();
      return;
    }
    if (!ok) {
      guest.close();
      setState(() => _joining = false);
      unawaited(_scanner.start());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't reach that party. Make sure both phones are on "
              'the same Wi-Fi or hotspot.')));
      return;
    }
    _sub?.cancel();
    _listener?.stop();
    _listener = null;
    await openPlayer(
      context,
      s,
      [
        PlayItem(
          uri: guest.videoUri,
          title: guest.video?.title ?? code.name,
          key: 'party',
          transient: true,
        ),
      ],
      party: guest,
      replace: true,
    );
  }

  Future<String> _myName() async {
    final s = widget.settings;
    return s.partyName.isNotEmpty ? s.partyName : SystemChannel.instance.deviceName();
  }

  /// Joins an online party: the link opens directly, a phone video is
  /// picked from this phone.
  Future<void> _joinOnline() async {
    final code = normalizeRoomCode(_code.text);
    final messenger = ScaffoldMessenger.of(context);
    if (code == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Party codes have 6 letters and numbers, like K7QF2M')));
      return;
    }
    if (_joining) return;
    setState(() => _joining = true);
    final name = await askOnlinePartyName(context, widget.settings);
    if (name == null) {
      if (mounted) setState(() => _joining = false);
      return;
    }
    OnlineParty party;
    try {
      party = await OnlineParty.join(name, code);
    } on OnlineException catch (e) {
      if (mounted) setState(() => _joining = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) {
      party.close();
      return;
    }
    final video = party.video;
    PlayItem? item = video.isLink
        ? PlayItem(uri: video.url!, title: video.title, key: 'party', transient: true)
        : await Navigator.push<PlayItem>(context,
            MaterialPageRoute(builder: (_) => PickVideoScreen(video: video)));
    if (item == null || !mounted) {
      party.close();
      if (mounted) setState(() => _joining = false);
      return;
    }
    await _scanner.stop();
    _sub?.cancel();
    _listener?.stop();
    _listener = null;
    if (!mounted) return;
    await openPlayer(context, widget.settings, [item], party: party, replace: true);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final code = JoinCode.parse(b.rawValue ?? '');
      if (code != null) {
        _join(code);
        return;
      }
    }
  }

  void _joinTyped() {
    final code = JoinCode.parse(_address.text);
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Type the address shown on the host, like 192.168.1.5')));
      return;
    }
    _join(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Watch together')),
      body: Column(
        children: [
          if (_joining) const LinearProgressIndicator(),
          Expanded(
            child: AbsorbPointer(
              absorbing: _joining,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Your friend opens a video, taps More, then Watch with friends.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text('Online, with a party code', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 7,
                          decoration: const InputDecoration(
                            hintText: 'K7QF2M',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _joinOnline(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _joinOnline, child: const Text('Join')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Nearby, on the same Wi-Fi', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text("Scan the code on your friend's screen",
                      style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox.square(
                        dimension: 250,
                        child: MobileScanner(
                          controller: _scanner,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                    'Camera not available. Pick a party below or type its address.',
                                    textAlign: TextAlign.center),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Parties nearby', style: theme.textTheme.titleMedium),
                  if (_found.isEmpty)
                    const ListTile(
                      leading: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      title: Text('Looking on this Wi-Fi...'),
                      subtitle: Text('Both phones need the same Wi-Fi, '
                          "or this phone on your friend's hotspot."),
                    ),
                  for (final h in _found)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.groups_rounded),
                        title: Text(h.name),
                        subtitle: Text(h.address),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _join(h.joinCode),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text('Or type the address', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _address,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: '192.168.1.5',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _joinTyped(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _joinTyped, child: const Text('Join')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const BannerAdSlot(),
        ],
      ),
    );
  }
}
