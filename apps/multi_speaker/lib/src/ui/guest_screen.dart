import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../net/party_guest.dart';
import '../platform/native.dart';
import '../settings.dart';
import '../speaker_delay.dart';
import '../sync/audio_engine.dart';
import '../sync/protocol.dart';
import '../sync/sync_controller.dart';
import 'common.dart';

/// This phone as one speaker of someone else's party.
class GuestScreen extends StatefulWidget {
  const GuestScreen({super.key, required this.settings, required this.code});

  final Settings settings;
  final JoinCode code;

  @override
  State<GuestScreen> createState() => _GuestScreenState();
}

class _GuestScreenState extends State<GuestScreen> {
  late final SpeakerDelay _delay = SpeakerDelay(widget.settings);
  PartyGuest? _guest;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _start();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && (_guest?.state.playing ?? false)) setState(() {});
    });
  }

  Future<void> _start() async {
    await Native.holdNetwork(true);
    final name = widget.settings.name ?? await Native.deviceName();
    final tmp = await getTemporaryDirectory();
    final folder = Directory('${tmp.path}/party_guest');
    if (await folder.exists()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    final guest = PartyGuest(
      engine: JustAudioEngine(),
      code: widget.code,
      name: name,
      folder: folder,
      latencyUs: _delay.latencyUs,
    );
    if (!mounted) return;
    setState(() => _guest = guest);
    await guest.connect();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _guest?.leave();
    _delay.dispose();
    Native.holdNetwork(false);
    super.dispose();
  }

  Future<void> _leave() async {
    final g = _guest;
    final live = g != null && g.status == GuestStatus.connected && g.state.playing;
    if (live &&
        !await confirmLeave(context,
            title: 'Leave the party?',
            body: 'This speaker stops. The others keep playing.',
            action: 'Leave')) {
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    AdService.instance.maybeShowInterstitial();
  }

  @override
  Widget build(BuildContext context) {
    final g = _guest;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.code.name)),
        body: Column(
          children: [
            Expanded(
              child: g == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListenableBuilder(listenable: g, builder: (context, _) => _body(g)),
            ),
            const BannerAdSlot(),
          ],
        ),
      ),
    );
  }

  Widget _body(PartyGuest g) {
    final theme = Theme.of(context);
    switch (g.status) {
      case GuestStatus.connecting:
        return const _Message(
            icon: Icons.wifi_find, text: 'Connecting to the party...', busy: true);
      case GuestStatus.failed:
        return _Message(
          icon: Icons.wifi_off,
          text: "Couldn't reach the host. Check that both phones are on the "
              "same Wi-Fi, or that this phone is on the host's hotspot.",
          action: FilledButton(onPressed: g.connect, child: const Text('Try again')),
        );
      case GuestStatus.hostLeft:
        return _Message(
          icon: Icons.celebration,
          text: 'The host ended the party.',
          action: FilledButton(onPressed: _leave, child: const Text('Done')),
        );
      case GuestStatus.connected:
      case GuestStatus.reconnecting:
        break;
    }
    final track = g.current;
    final duration = g.sync.duration ?? Duration.zero;
    final pos = g.position;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (g.status == GuestStatus.reconnecting)
          Card(
            color: theme.colorScheme.errorContainer,
            child: const ListTile(
              leading: Icon(Icons.wifi_off),
              title: Text('Lost the host. Reconnecting...'),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ValueListenableBuilder(
                  valueListenable: g.sync.phase,
                  builder: (context, phase, _) =>
                      SpeakerPulse(playing: phase == SyncPhase.playing, size: 64),
                ),
                Text(track?.title ?? 'Waiting for the host to pick a song',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                SyncChip(
                    sync: g.sync,
                    downloadProgress:
                        track == null ? null : g.downloading[track.id]),
                if (g.sync.phase.value == SyncPhase.pausedHere)
                  TextButton.icon(
                    onPressed: g.sync.rejoin,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play here again'),
                  ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: duration.inMilliseconds == 0
                      ? 0
                      : (pos.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0),
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(formatTime(pos)), Text(formatTime(duration))],
                ),
                const SizedBox(height: 4),
                Text('The host controls the music. Use the volume buttons on '
                    'this phone or speaker.',
                    textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        DelayTile(delay: _delay),
        const SizedBox(height: 16),
        Text('Up next', style: theme.textTheme.titleMedium),
        for (final t in g.playlist)
          ListTile(
            dense: true,
            leading: Icon(t.id == g.state.trackId ? Icons.graphic_eq : Icons.music_note,
                color: t.id == g.state.trackId ? theme.colorScheme.primary : null),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: g.downloading.containsKey(t.id)
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, value: g.downloading[t.id]))
                : null,
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action, this.busy = false});

  final IconData icon;
  final String text;
  final Widget? action;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (busy) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
