import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../player/play_item.dart';
import '../player/player_screen.dart';
import '../player/system_channel.dart';
import '../settings.dart';
import 'discovery.dart';
import 'party.dart';
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
    if (!_joining) SystemChannel.instance.holdNetwork(false);
    super.dispose();
  }

  Future<void> _join(JoinCode code) async {
    if (_joining) return;
    setState(() => _joining = true);
    await _scanner.stop();
    final s = widget.settings;
    final name = s.partyName.isNotEmpty
        ? s.partyName
        : await SystemChannel.instance.deviceName();
    final guest = PartyGuest(name, code);
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
                    'Your friend opens a video, taps More, then Watch with friends. '
                    'Scan the code on their screen to watch in sync, with chat and reactions.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
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
