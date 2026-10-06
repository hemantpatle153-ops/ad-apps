import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../net/party_host.dart';
import '../platform/native.dart';
import '../settings.dart';
import '../speaker_delay.dart';
import '../sync/audio_engine.dart';
import '../sync/sync_controller.dart';
import 'common.dart';
import 'widgets.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key, required this.settings});

  final Settings settings;

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  late final SpeakerDelay _delay = SpeakerDelay(widget.settings);
  PartyHost? _host;
  Directory? _folder;
  String? _error;
  bool _adding = false;
  Timer? _clock;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _start();
    // Moves the progress bar along.
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && (_host?.state.playing ?? false)) setState(() {});
    });
  }

  Future<void> _start() async {
    try {
      await Native.holdNetwork(true);
      final name = widget.settings.name ?? await Native.deviceName();
      final tmp = await getTemporaryDirectory();
      final folder = Directory('${tmp.path}/party_host');
      if (await folder.exists()) await folder.delete(recursive: true);
      await folder.create(recursive: true);
      final host = PartyHost(
          engine: JustAudioEngine(), name: name, speaker: _delay);
      await host.start();
      if (!mounted) {
        await host.close();
        return;
      }
      setState(() {
        _host = host;
        _folder = folder;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _host?.close();
    _delay.dispose();
    Native.holdNetwork(false);
    super.dispose();
  }

  Future<void> _addSongs() async {
    final host = _host;
    final folder = _folder;
    if (host == null || folder == null) return;
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty) return;
    setState(() => _adding = true);
    try {
      var n = 0;
      for (final f in files) {
        // Copy into our own folder: picked files can be content links that
        // we can't serve to other phones directly.
        final ext = f.extension ?? 'mp3';
        final dest = File('${folder.path}/${DateTime.now().microsecondsSinceEpoch}_${n++}.$ext');
        final sink = dest.openWrite();
        await sink.addStream(f.readAsByteStream());
        await sink.close();
        final dot = f.name.lastIndexOf('.');
        await host.addTrack(dest.path, dot > 0 ? f.name.substring(0, dot) : f.name);
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't add that song: $e")));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _leave() async {
    final host = _host;
    final hasGuests = host != null && host.guests.isNotEmpty;
    if (hasGuests &&
        !await confirmLeave(context,
            title: 'End the party?',
            body: 'The music stops on every speaker.',
            action: 'End party')) {
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    // A natural break: the party is over.
    AdService.instance.maybeShowInterstitial();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your party'),
          leading: IconButton(
            tooltip: 'End party',
            icon: const Icon(Icons.close),
            onPressed: _leave,
          ),
          actions: [
            IconButton(
              tooltip: 'Bluetooth settings',
              icon: const Icon(Icons.bluetooth),
              onPressed: Native.openBluetoothSettings,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _body(host)),
            const BannerAdSlot(),
          ],
        ),
        bottomNavigationBar: host == null
            ? null
            : ListenableBuilder(
                listenable: host,
                builder: (context, _) => NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    const NavigationDestination(
                        icon: Icon(Icons.music_note_outlined),
                        selectedIcon: Icon(Icons.music_note),
                        label: 'Music'),
                    NavigationDestination(
                      icon: Badge(
                        label: Text('${host.guests.length + 1}'),
                        child: const Icon(Icons.speaker_group_outlined),
                      ),
                      selectedIcon: Badge(
                        label: Text('${host.guests.length + 1}'),
                        child: const Icon(Icons.speaker_group),
                      ),
                      label: 'Speakers',
                    ),
                    const NavigationDestination(
                        icon: Icon(Icons.qr_code_2_outlined),
                        selectedIcon: Icon(Icons.qr_code_2),
                        label: 'Invite'),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _body(PartyHost? host) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text("Couldn't start the party: $_error", textAlign: TextAlign.center),
        ),
      );
    }
    if (host == null) return const Center(child: CircularProgressIndicator());
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) => switch (_tab) {
        0 => _MusicTab(host: host, adding: _adding, onAdd: _addSongs),
        1 => _SpeakersTab(
            host: host, delay: _delay, onInvite: () => setState(() => _tab = 2)),
        _ => _InviteTab(host: host),
      },
    );
  }
}

class _MusicTab extends StatelessWidget {
  const _MusicTab({required this.host, required this.adding, required this.onAdd});

  final PartyHost host;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      header: Column(
        children: [
          _NowPlaying(host: host),
          SectionHeader(
            'Up next',
            trailing: FilledButton.tonalIcon(
              onPressed: adding ? null : onAdd,
              icon: adding
                  ? const SizedBox.square(
                      dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('Add songs'),
            ),
          ),
          if (host.playlist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.library_music_outlined,
                      size: 56, color: theme.colorScheme.outline),
                  const SizedBox(height: 8),
                  const Text('Add songs from this phone to start the party.',
                      textAlign: TextAlign.center),
                ],
              ),
            ),
        ],
      ),
      itemCount: host.playlist.length,
      onReorderItem: host.moveTrack,
      itemBuilder: (context, i) {
        final t = host.playlist[i];
        final isCurrent = t.id == host.state.trackId;
        return Card(
          key: ValueKey(t.id),
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: isCurrent ? theme.colorScheme.primaryContainer : null,
          child: ListTile(
            leading: ArtworkTile(title: t.title, size: 44),
            title: Text(t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isCurrent ? const TextStyle(fontWeight: FontWeight.w700) : null),
            subtitle: Text(_readyText(host, t.id)),
            onTap: () => host.playTrack(t.id),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCurrent && host.state.playing)
                  Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () => host.removeTrack(t.id),
                ),
                ReorderableDragStartListener(
                    index: i, child: const Icon(Icons.drag_handle)),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _readyText(PartyHost host, String id) {
    if (host.guests.isEmpty) return 'Ready';
    final ready = host.guests.where((g) => g.ready.contains(id)).length;
    return ready == host.guests.length
        ? 'Ready on every speaker'
        : 'Sending to speakers ($ready of ${host.guests.length})';
  }
}

class _NowPlaying extends StatefulWidget {
  const _NowPlaying({required this.host});

  final PartyHost host;

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  /// Where the finger is while dragging the progress bar.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final track = host.current;
    final duration = host.sync.duration ?? Duration.zero;
    final pos = _drag == null ? host.position : Duration(milliseconds: _drag!.round());
    final theme = Theme.of(context);
    final speakers = host.guests.length + 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          children: [
            ArtworkTile(title: track?.title, size: 168, playing: host.state.playing),
            const SizedBox(height: 16),
            Text(track?.title ?? 'No song yet',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              speakers == 1
                  ? 'Playing on this phone. Invite more speakers.'
                  : 'Playing on $speakers speakers',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            SyncChip(sync: host.sync),
            const SizedBox(height: 4),
            Slider(
              value: duration.inMilliseconds == 0
                  ? 0
                  : pos.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
              max: duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds.toDouble(),
              onChanged: track == null || duration == Duration.zero
                  ? null
                  : (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                setState(() => _drag = null);
                host.seek(Duration(milliseconds: v.round()));
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatTime(pos), style: theme.textTheme.labelMedium),
                  Text(formatTime(duration), style: theme.textTheme.labelMedium),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: host.repeat ? 'Repeat is on' : 'Repeat is off',
                  onPressed: host.toggleRepeat,
                  icon: Icon(Icons.repeat,
                      color: host.repeat ? theme.colorScheme.primary : null),
                ),
                IconButton(
                  iconSize: 36,
                  tooltip: 'Previous',
                  onPressed: track == null ? null : host.previous,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton.filled(
                  iconSize: 44,
                  style: IconButton.styleFrom(minimumSize: const Size(72, 72)),
                  tooltip: host.state.playing ? 'Pause' : 'Play',
                  onPressed: host.playlist.isEmpty ? null : host.togglePlay,
                  icon: Icon(host.state.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                ),
                IconButton(
                  iconSize: 36,
                  tooltip: 'Next',
                  onPressed: track == null ? null : host.next,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                IconButton(
                  tooltip: host.level.muted ? 'Unmute this phone' : 'Mute this phone',
                  onPressed: () =>
                      host.setLevel(host.level.copyWith(muted: !host.level.muted)),
                  icon: Icon(host.level.muted ? Icons.volume_off : Icons.volume_up,
                      color: host.level.muted ? theme.colorScheme.error : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeakersTab extends StatelessWidget {
  const _SpeakersTab({required this.host, required this.delay, required this.onInvite});

  final PartyHost host;
  final SpeakerDelay delay;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final id = host.state.trackId;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SectionHeader(
          '${host.guests.length + 1} speaker${host.guests.isEmpty ? '' : 's'}',
          trailing: FilledButton.tonalIcon(
            onPressed: onInvite,
            icon: const Icon(Icons.add),
            label: const Text('Add speaker'),
          ),
        ),
        ListenableBuilder(
          listenable: delay,
          builder: (context, _) => SpeakerCard(
            name: host.name,
            output: delay.outputLabel,
            bluetooth: delay.bluetooth,
            isThisPhone: true,
            level: host.level,
            onLevel: host.setLevel,
            delayMs: delay.delayMs,
            onDelay: (ms) => delay.delayMs = ms,
            status: _status(host.sync.phase.value, host.sync.errorMs.value),
            statusColor: _statusColor(scheme, host.sync.phase.value),
          ),
        ),
        for (final g in host.guests)
          SpeakerCard(
            key: ObjectKey(g),
            name: g.name,
            output: g.output,
            bluetooth: g.bluetooth,
            level: g.level,
            onLevel: (l) => host.setGuestLevel(g, l),
            delayMs: g.delayMs,
            onDelay: (ms) => host.setGuestDelay(g, ms),
            status: id != null && !g.ready.contains(id)
                ? 'Getting song'
                : g.errorMs == null
                    ? 'Ready'
                    : 'In sync',
            statusColor: id != null && !g.ready.contains(id)
                ? scheme.tertiary
                : Colors.green.shade600,
            onRemove: () => host.kick(g),
          ),
        const SizedBox(height: 12),
        Card(
          color: scheme.secondaryContainer,
          child: const ListTile(
            leading: Icon(Icons.lightbulb_outline),
            title: Text('One phone per Bluetooth speaker'),
            subtitle: Text('Android plays Bluetooth music to one speaker per phone. '
                'Connect each phone to its own speaker, then join this party from it. '
                'Change any speaker\'s volume here.'),
          ),
        ),
      ],
    );
  }

  static String? _status(SyncPhase p, int? err) => switch (p) {
        SyncPhase.playing => 'In sync',
        SyncPhase.starting => 'Starting',
        SyncPhase.pausedHere => 'Paused here',
        SyncPhase.waitingForSong => 'Getting song',
        _ => null,
      };

  static Color _statusColor(ColorScheme s, SyncPhase p) => switch (p) {
        SyncPhase.playing => Colors.green.shade600,
        SyncPhase.pausedHere => s.error,
        _ => s.tertiary,
      };
}

class _InviteTab extends StatelessWidget {
  const _InviteTab({required this.host});

  final PartyHost host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noNetwork = host.addresses.isEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('Add a speaker',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'On another phone: connect its Bluetooth speaker, open Multi Speaker, '
          'tap Join a party and scan this code.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (noNetwork)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.wifi_off, size: 48),
                  const SizedBox(height: 8),
                  const Text('This phone is not on Wi-Fi. Connect to Wi-Fi or turn '
                      'on the hotspot, then tap Refresh.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                          onPressed: Native.openHotspotSettings,
                          child: const Text('Hotspot settings')),
                      FilledButton(
                          onPressed: host.refreshAddresses, child: const Text('Refresh')),
                    ],
                  ),
                ],
              ),
            ),
          )
        else ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16)],
              ),
              child: QrImageView(
                data: host.joinCode.encode(),
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Or type ${host.addresses.first} on the other phone',
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          TextButton.icon(
            onPressed: host.refreshAddresses,
            icon: const Icon(Icons.refresh),
            label: const Text('Changed Wi-Fi? Refresh code'),
          ),
        ],
        const SizedBox(height: 12),
        const Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.wifi),
                title: Text('Same Wi-Fi'),
                subtitle: Text("Every phone on the same Wi-Fi network, or on this phone's hotspot."),
              ),
              ListTile(
                leading: Icon(Icons.bluetooth_audio),
                title: Text('One speaker per phone'),
                subtitle: Text('Each phone plays on its own Bluetooth or built-in speaker.'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
