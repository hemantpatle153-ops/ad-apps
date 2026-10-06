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
import 'common.dart';

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
          engine: JustAudioEngine(), name: name, latencyUs: _delay.latencyUs);
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

  Future<void> _showInvite() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: _InviteCard(host: _host!, elevated: false),
          ),
        ),
      );

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
          actions: [
            if (host != null)
              IconButton(
                tooltip: 'Invite',
                icon: const Icon(Icons.qr_code),
                onPressed: _showInvite,
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _body(host)),
            const BannerAdSlot(),
          ],
        ),
        floatingActionButton: host == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _adding ? null : _addSongs,
                icon: _adding
                    ? const SizedBox.square(
                        dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.library_add),
                label: const Text('Add songs'),
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
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _NowPlaying(host: host),
          const SizedBox(height: 8),
          if (host.guests.isEmpty) _InviteCard(host: host) else _Speakers(host: host, delay: _delay),
          if (host.guests.isEmpty) ...[
            const SizedBox(height: 8),
            DelayTile(delay: _delay),
          ],
          const SizedBox(height: 16),
          Text('Playlist', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (host.playlist.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Tap Add songs to pick music from this phone.',
                  textAlign: TextAlign.center),
            ),
          for (final (i, t) in host.playlist.indexed)
            Card(
              child: ListTile(
                leading: t.id == host.state.trackId
                    ? Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary)
                    : CircleAvatar(radius: 14, child: Text('${i + 1}')),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_readyText(host, t.id)),
                onTap: () => host.playTrack(t.id),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () => host.removeTrack(t.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _readyText(PartyHost host, String id) {
    if (host.guests.isEmpty) return 'Ready';
    final ready = host.guests.where((g) => g.ready.contains(id)).length;
    return ready == host.guests.length
        ? 'Ready on all phones'
        : 'Sending to phones ($ready of ${host.guests.length})';
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: [
            SpeakerPulse(playing: host.state.playing, size: 56),
            Text(track?.title ?? 'No song yet',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            SyncChip(sync: host.sync),
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
                children: [Text(formatTime(pos)), Text(formatTime(duration))],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 36,
                  tooltip: 'Previous',
                  onPressed: track == null ? null : host.previous,
                  icon: const Icon(Icons.skip_previous),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  iconSize: 48,
                  tooltip: host.state.playing ? 'Pause' : 'Play',
                  onPressed: host.playlist.isEmpty ? null : host.togglePlay,
                  icon: Icon(host.state.playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 12),
                IconButton(
                  iconSize: 36,
                  tooltip: 'Next',
                  onPressed: track == null ? null : host.next,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.host, this.elevated = true});

  final PartyHost host;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noNetwork = host.addresses.isEmpty;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Invite more speakers', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'On another phone, open Multi Speaker, tap Join a party and scan '
            'this code. Both phones must be on the same Wi-Fi, or on this '
            "phone's hotspot.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (noNetwork) ...[
            const Icon(Icons.wifi_off, size: 48),
            const SizedBox(height: 8),
            const Text('This phone is not on Wi-Fi. Connect to Wi-Fi or turn '
                'on the hotspot, then tap Refresh.',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                    onPressed: Native.openHotspotSettings,
                    child: const Text('Hotspot settings')),
                FilledButton(
                    onPressed: host.refreshAddresses, child: const Text('Refresh')),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(
                data: host.joinCode.encode(),
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text('Or type: ${host.addresses.first}',
                style: theme.textTheme.bodySmall),
            TextButton(
                onPressed: host.refreshAddresses,
                child: const Text('Changed Wi-Fi? Refresh code')),
          ],
        ],
      ),
    );
    return elevated ? Card(child: content) : content;
  }
}

class _Speakers extends StatelessWidget {
  const _Speakers({required this.host, required this.delay});

  final PartyHost host;
  final SpeakerDelay delay;

  @override
  Widget build(BuildContext context) {
    final id = host.state.trackId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Speakers (${host.guests.length + 1})',
            style: Theme.of(context).textTheme.titleMedium),
        DelayTile(delay: delay),
        for (final g in host.guests)
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(g.name),
              subtitle: Text(id == null
                  ? 'Connected'
                  : !g.ready.contains(id)
                      ? 'Getting the song...'
                      : g.errorMs == null
                          ? 'Ready'
                          : 'In sync (${g.errorMs!.abs()} ms)'),
            ),
          ),
      ],
    );
  }
}
