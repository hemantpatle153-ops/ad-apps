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
import 'widgets.dart';

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
      speaker: _delay,
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
      case GuestStatus.removed:
        return _Message(
          icon: Icons.person_remove_outlined,
          text: 'The host removed this phone from the party.',
          action: FilledButton(onPressed: _leave, child: const Text('Done')),
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
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (g.status == GuestStatus.reconnecting)
          Card(
            color: scheme.errorContainer,
            child: const ListTile(
              leading: Icon(Icons.wifi_off),
              title: Text('Lost the host. Reconnecting...'),
              subtitle: Text('The music keeps playing meanwhile.'),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              children: [
                ValueListenableBuilder(
                  valueListenable: g.sync.phase,
                  builder: (context, phase, _) => ArtworkTile(
                      title: track?.title,
                      size: 168,
                      playing: phase == SyncPhase.playing),
                ),
                const SizedBox(height: 16),
                Text(track?.title ?? 'Waiting for the host to pick a song',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('From ${widget.code.name}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
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
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: duration.inMilliseconds == 0
                      ? 0
                      : (pos.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatTime(pos), style: theme.textTheme.labelMedium),
                    Text(formatTime(duration), style: theme.textTheme.labelMedium),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SectionHeader('This speaker'),
        ListenableBuilder(
          listenable: _delay,
          builder: (context, _) => SpeakerCard(
            name: widget.settings.name ?? 'This phone',
            output: _delay.outputLabel,
            bluetooth: _delay.bluetooth,
            isThisPhone: true,
            level: g.level,
            onLevel: g.setLevel,
            delayMs: _delay.delayMs,
            onDelay: (ms) => _delay.delayMs = ms,
            footer: _delay.bluetooth
                ? null
                : Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
                    child: OutlinedButton.icon(
                      onPressed: Native.openBluetoothSettings,
                      icon: const Icon(Icons.bluetooth),
                      label: const Text('Connect a Bluetooth speaker'),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('The host can change this speaker\'s volume and delay too.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        if (g.playlist.isNotEmpty) const SectionHeader('Up next'),
        for (final t in g.playlist)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: ArtworkTile(title: t.title, size: 40),
            title: Text(t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.id == g.state.trackId
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null),
            trailing: g.downloading.containsKey(t.id)
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, value: g.downloading[t.id]))
                : t.id == g.state.trackId
                    ? Icon(Icons.graphic_eq, color: scheme.primary)
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
