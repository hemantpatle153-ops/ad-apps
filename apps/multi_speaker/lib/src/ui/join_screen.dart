import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../net/discovery.dart';
import '../platform/native.dart';
import '../settings.dart';
import '../sync/protocol.dart';
import 'guest_screen.dart';

/// Finds a party: scan the host's QR code, tap one found nearby, or type
/// the address shown on the host.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.settings});

  final Settings settings;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
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
    await Native.holdNetwork(true);
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
    super.dispose();
  }

  Future<void> _join(JoinCode code) async {
    if (_joining) return;
    _joining = true;
    _sub?.cancel();
    _listener?.stop();
    _listener = null;
    await _scanner.stop();
    if (!mounted) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => GuestScreen(settings: widget.settings, code: code)),
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
      appBar: AppBar(title: const Text('Join a party')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text("Scan the code on the host's screen",
                    style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox.square(
                      dimension: 260,
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
                    subtitle: Text('Make sure this phone is on the same Wi-Fi '
                        "or on the host's hotspot."),
                  ),
                for (final h in _found)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.speaker_group),
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
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
          const BannerAdSlot(),
        ],
      ),
    );
  }
}
