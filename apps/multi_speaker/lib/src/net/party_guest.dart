import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../sync/audio_engine.dart';
import '../sync/clock.dart';
import '../sync/protocol.dart';
import '../sync/speaker.dart';
import '../sync/sync_controller.dart';

enum GuestStatus { connecting, connected, reconnecting, hostLeft, removed, failed }

/// A phone that joined someone's party: it copies the host's songs over the
/// local network and plays them on the host's timeline.
class PartyGuest extends ChangeNotifier {
  PartyGuest({
    required this.engine,
    required this.code,
    required this.name,
    required this.folder,
    required this.speaker,
  }) {
    sync = SyncController(
      engine: engine,
      hostNowUs: hostNowUs,
      latencyUs: speaker.latencyUs,
      trackPath: (id) => _paths[id],
      trackTitle: (id) => _track(id)?.title ?? 'Song',
    );
    speaker.addListener(_sendInfo);
  }

  /// This phone's output and delay; the host can change the delay.
  final LocalSpeaker speaker;

  /// This speaker's volume in the party. The host can change it too.
  SpeakerLevel level = const SpeakerLevel();

  final AudioEngine engine;
  final JoinCode code;
  final String name;

  /// Where downloaded songs go; emptied when leaving.
  final Directory folder;
  late final SyncController sync;
  final ClockSync clock = ClockSync();

  GuestStatus status = GuestStatus.connecting;
  String? hostAddress;
  List<Track> playlist = [];
  PlayState state = PlayState.idle;

  /// Download progress (0..1) per song still downloading.
  final Map<String, double> downloading = {};
  final Map<String, String> _paths = {};

  WebSocket? _ws;
  Timer? _pinger;
  bool _closed = false;
  bool _downloadRunning = false;
  Completer<void> _clockReady = Completer();
  HttpClient? _http;

  int hostNowUs() => Clock.nowUs() + clock.offsetUs;

  Track? get current => _track(state.trackId);

  Track? _track(String? id) {
    for (final t in playlist) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Song position on the timeline, for the progress bar.
  Duration get position {
    var us = state.positionAt(hostNowUs());
    if (us < 0) us = 0;
    final end = sync.duration?.inMicroseconds;
    if (end != null && us > end) us = end;
    return Duration(microseconds: us);
  }

  Future<void> connect() async {
    status = GuestStatus.connecting;
    notifyListeners();
    if (!await _open()) {
      status = GuestStatus.failed;
      notifyListeners();
    }
  }

  /// Tries every address in the join code and keeps the first that answers.
  Future<bool> _open() async {
    for (final h in [?hostAddress, ...code.hosts]) {
      if (_closed) return false;
      try {
        final ws = await WebSocket.connect('ws://$h:${code.port}/ws')
            .timeout(const Duration(seconds: 3));
        ws.pingInterval = const Duration(seconds: 5);
        hostAddress = h;
        _attach(ws);
        return true;
      } on Object {
        // Try the next address.
      }
    }
    return false;
  }

  void _attach(WebSocket ws) {
    _ws = ws;
    status = GuestStatus.connected;
    // After a reconnect the clock estimate is still good: keep it so the
    // music doesn't jump while new samples arrive.
    _pongs = 0;
    if (!clock.hasEstimate) _clockReady = Completer();
    ws.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
    _send('hi', {'name': name, 'v': protocolVersion});
    _sendInfo();
    for (final id in _paths.keys) {
      _send('ready', {'id': id});
    }
    _startPinging();
    _download();
    notifyListeners();
  }

  /// Sets this speaker's volume here and tells the host.
  void setLevel(SpeakerLevel l) {
    _applyLevel(l);
    _sendInfo();
  }

  void _applyLevel(SpeakerLevel l) {
    level = l;
    engine.setVolume(l.effective);
    notifyListeners();
  }

  /// Tells the host how this speaker is set up, for its speakers list.
  void _sendInfo() => _send('info', {
        'vol': (level.volume * 100).round(),
        'muted': level.muted,
        'delay': speaker.delayMs,
        'out': speaker.outputLabel,
        'bt': speaker.bluetooth,
      });

  void _send(String type, [Map<String, Object?> body = const {}]) {
    try {
      _ws?.add(encodeMessage(type, body));
    } on Object {
      // Closed; _onClosed handles it.
    }
  }

  /// A quick burst of pings to learn the host's clock, then one every 1.5 s
  /// to follow it (phone clocks drift a little).
  void _startPinging() {
    _pinger?.cancel();
    var burst = 12;
    void ping() => _send('ping', {'c': Clock.nowUs(), 'err': sync.errorMs.value});
    _pinger = Timer.periodic(const Duration(milliseconds: 120), (t) {
      ping();
      if (--burst == 0) {
        t.cancel();
        _pinger = Timer.periodic(const Duration(milliseconds: 1500), (_) => ping());
      }
    });
  }

  void _onMessage(Object? data) {
    final now = Clock.nowUs();
    final m = decodeMessage(data);
    if (m == null) return;
    switch (m['t']) {
      case 'pong':
        if (m['c'] case final int sent) {
          clock.add(sentUs: sent, hostUs: m['h'] as int, receivedUs: now);
          if (!_clockReady.isCompleted && clock.bestRttUs != null) {
            // A few samples are enough to start; more refine it as we play.
            if (_pongs++ >= 5) _clockReady.complete();
          }
        }
      case 'playlist':
        playlist = [
          for (final t in (m['tracks'] as List).cast<Map<String, Object?>>())
            Track.fromJson(t)
        ];
        _dropRemoved();
        _download();
        notifyListeners();
      case 'state':
        state = PlayState.fromJson(m);
        notifyListeners();
        _applyWhenClockReady(state);
        _download();
      case 'set':
        // The host changed this speaker from its speakers list.
        final vol = m['vol'];
        final muted = m['muted'];
        if (vol is int || muted is bool) {
          _applyLevel(level.copyWith(
            volume: vol is int ? vol.clamp(0, 100) / 100 : null,
            muted: muted is bool ? muted : null,
          ));
        }
        if (m['delay'] case final int delay) {
          speaker.delayMs = delay; // Its listener reports back to the host.
        } else {
          _sendInfo();
        }
      case 'kick':
        status = GuestStatus.removed;
        sync.stop();
        notifyListeners();
      case 'bye':
        status = GuestStatus.hostLeft;
        sync.stop();
        notifyListeners();
    }
  }

  int _pongs = 0;

  Future<void> _applyWhenClockReady(PlayState s) async {
    await _clockReady.future.timeout(const Duration(seconds: 3),
        onTimeout: () {});
    if (identical(s, state) && !_closed) await sync.apply(s);
  }

  void _dropRemoved() {
    final keep = playlist.map((t) => t.id).toSet();
    for (final id in _paths.keys.where((id) => !keep.contains(id)).toList()) {
      File(_paths.remove(id)!).delete().ignore();
    }
  }

  /// Downloads songs one at a time, the playing one first, then the rest
  /// of the playlist in order so the next song is ready when it comes.
  Future<void> _download() async {
    if (_downloadRunning) return;
    _downloadRunning = true;
    try {
      while (!_closed && status == GuestStatus.connected) {
        final missing = playlist.where((t) => !_paths.containsKey(t.id)).toList();
        if (missing.isEmpty) break;
        final t = missing.firstWhere((t) => t.id == state.trackId,
            orElse: () => missing.first);
        if (!await _fetch(t)) break;
      }
    } finally {
      _downloadRunning = false;
    }
  }

  Future<bool> _fetch(Track t) async {
    final host = hostAddress;
    if (host == null) return false;
    final file = File('${folder.path}/${t.id}.${t.ext}');
    final part = File('${file.path}.part');
    downloading[t.id] = 0;
    notifyListeners();
    try {
      final http = _http ??= HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await http.getUrl(Uri.parse('http://$host:${code.port}/track/${t.id}'));
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        return true; // Removed from the playlist meanwhile.
      }
      final sink = part.openWrite();
      var got = 0;
      var lastShown = 0.0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        final p = t.size == 0 ? 0.0 : got / t.size;
        if (p - lastShown > 0.02) {
          lastShown = p;
          downloading[t.id] = p;
          notifyListeners();
        }
      }
      await sink.close();
      await part.rename(file.path);
      _paths[t.id] = file.path;
      _send('ready', {'id': t.id});
      sync.trackAvailable(t.id);
      return true;
    } on Object {
      part.delete().ignore();
      return false;
    } finally {
      downloading.remove(t.id);
      notifyListeners();
    }
  }

  void _onClosed() {
    _pinger?.cancel();
    _ws = null;
    if (_closed ||
        status == GuestStatus.hostLeft ||
        status == GuestStatus.removed) {
      return;
    }
    status = GuestStatus.reconnecting;
    notifyListeners();
    _reconnect();
  }

  /// Wi-Fi blips are common; keep the music going and try again.
  Future<void> _reconnect() async {
    while (!_closed && status == GuestStatus.reconnecting) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_closed) return;
      if (await _open()) return;
    }
  }

  Future<void> leave() async {
    _closed = true;
    speaker.removeListener(_sendInfo);
    _pinger?.cancel();
    await _ws?.close();
    _http?.close(force: true);
    await sync.dispose();
    for (final p in _paths.values) {
      File(p).delete().ignore();
    }
  }
}
