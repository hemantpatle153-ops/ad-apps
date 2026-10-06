import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../sync/audio_engine.dart';
import '../sync/clock.dart';
import '../sync/protocol.dart';
import '../sync/sync_controller.dart';
import 'discovery.dart';

/// A phone that joined the party.
class Guest {
  Guest(this.socket, this.address);

  final WebSocket socket;
  final String address;
  String name = 'Phone';
  final Set<String> ready = {};

  /// How far its speaker is from the timeline, as it last reported.
  int? errorMs;

  void send(String message) {
    try {
      socket.add(message);
    } on Object {
      // Closed; the done handler removes it.
    }
  }
}

/// The phone that owns the music. It serves the songs to guests, decides
/// what plays when, and plays along on its own speaker.
///
/// Everything runs on this phone and the local network: no internet and no
/// server needed.
class PartyHost extends ChangeNotifier {
  PartyHost({
    required this.engine,
    required this.name,
    required int Function() latencyUs,
  }) {
    sync = SyncController(
      engine: engine,
      hostNowUs: Clock.nowUs,
      latencyUs: latencyUs,
      trackPath: (id) => _paths[id],
      trackTitle: (id) => _track(id)?.title ?? 'Song',
    );
    sync.onPausedHere = () => pause();
  }

  final AudioEngine engine;
  final String name;
  late final SyncController sync;

  /// How far ahead a start is scheduled, so every phone has time to seek.
  static const startLead = Duration(milliseconds: 700);

  /// How long to wait for slow guests to finish downloading a song.
  static const readyTimeout = Duration(seconds: 8);

  HttpServer? _server;
  Beacon? _beacon;
  List<String> addresses = [];
  int get port => _server?.port ?? hostPort;

  final List<Track> playlist = [];
  final Map<String, String> _paths = {};
  final List<Guest> guests = [];
  PlayState state = PlayState.idle;
  final _rng = Random.secure();
  int _op = 0;
  StreamSubscription<void>? _completedSub;

  JoinCode get joinCode => JoinCode(hosts: addresses, port: port, name: name);

  Track? get current => _track(state.trackId);
  int get currentIndex => playlist.indexWhere((t) => t.id == state.trackId);

  Track? _track(String? id) {
    for (final t in playlist) {
      if (t.id == id) return t;
    }
    return null;
  }

  Duration get position {
    var us = max(0, state.positionAt(Clock.nowUs()));
    final end = sync.duration?.inMicroseconds;
    if (end != null && us > end) us = end;
    return Duration(microseconds: us);
  }

  Future<void> start({bool beacon = true}) async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, hostPort);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen(_handle, onError: (_) {});
    addresses = await localAddresses();
    if (beacon) {
      _beacon = await Beacon.start(name: name, port: port, addresses: addresses);
    }
    _completedSub = engine.completed.listen((_) {
      if (state.playing) next(fromEnd: true);
    });
    notifyListeners();
  }

  /// Re-reads this phone's addresses, e.g. after turning on the hotspot.
  Future<void> refreshAddresses() async {
    addresses = await localAddresses();
    _beacon?.stop();
    _beacon = await Beacon.start(name: name, port: port, addresses: addresses);
    notifyListeners();
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.pingInterval = const Duration(seconds: 5);
      final g = Guest(ws, req.connectionInfo?.remoteAddress.address ?? '?');
      guests.add(g);
      ws.listen((data) => _onMessage(g, data),
          onDone: () => _drop(g), onError: (_) => _drop(g));
      notifyListeners();
      return;
    }
    if (path.startsWith('/track/')) {
      final file = _paths[path.substring('/track/'.length)];
      if (file != null) {
        final f = File(file);
        req.response.headers
          ..contentType = ContentType.binary
          ..contentLength = await f.length();
        await req.response.addStream(f.openRead());
        await req.response.close();
        return;
      }
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  void _onMessage(Guest g, Object? data) {
    final m = decodeMessage(data);
    if (m == null) return;
    switch (m['t']) {
      case 'ping':
        // Answer first: any delay here becomes clock error.
        g.send(encodeMessage('pong', {'c': m['c'], 'h': Clock.nowUs()}));
        final err = m['err'];
        if (err != g.errorMs && (err == null || err is int)) {
          g.errorMs = err as int?;
          notifyListeners();
        }
      case 'hi':
        g.name = '${m['name'] ?? 'Phone'}';
        g.send(encodeMessage(
            'playlist', {'tracks': [for (final t in playlist) t.toJson()]}));
        g.send(encodeMessage('state', state.toJson()));
        notifyListeners();
      case 'ready':
        if (m['id'] case final String id) g.ready.add(id);
        notifyListeners();
    }
  }

  void _drop(Guest g) {
    if (guests.remove(g)) notifyListeners();
  }

  void _broadcast(String message) {
    for (final g in guests) {
      g.send(message);
    }
  }

  /// Adds a song file that is already in this phone's party folder.
  Future<void> addTrack(String path, String title) async {
    final id = List.generate(8, (_) => _rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? 'mp3' : path.substring(dot + 1).toLowerCase();
    final t = Track(
        id: id, title: title, ext: ext, size: await File(path).length());
    playlist.add(t);
    _paths[id] = path;
    _sendPlaylist();
    if (state.trackId == null) await _setState(_pausedAt(id, 0));
    notifyListeners();
  }

  Future<void> removeTrack(String id) async {
    final wasCurrent = state.trackId == id;
    final index = playlist.indexWhere((t) => t.id == id);
    if (index < 0) return;
    playlist.removeAt(index);
    _sendPlaylist();
    if (wasCurrent) {
      if (playlist.isEmpty) {
        await _setState(PlayState.idle);
      } else {
        await playTrack(playlist[min(index, playlist.length - 1)].id,
            autoplay: state.playing);
      }
    }
    final path = _paths.remove(id);
    if (path != null) _deleteQuietly(path);
    notifyListeners();
  }

  void _sendPlaylist() => _broadcast(encodeMessage(
      'playlist', {'tracks': [for (final t in playlist) t.toJson()]}));

  PlayState _pausedAt(String id, int us) =>
      PlayState(trackId: id, playing: false, positionUs: us, anchorUs: 0);

  PlayState _playingFrom(String id, int us) => PlayState(
      trackId: id,
      playing: true,
      positionUs: us,
      anchorUs: Clock.nowUs() + startLead.inMicroseconds);

  Future<void> playTrack(String id, {bool autoplay = true}) async {
    final op = ++_op;
    await _setState(_pausedAt(id, 0));
    if (!autoplay) return;
    await _waitForGuests(id);
    if (op != _op) return;
    await _setState(_playingFrom(id, 0));
  }

  Future<void> play() async {
    final id = state.trackId;
    if (id == null) {
      if (playlist.isNotEmpty) await playTrack(playlist.first.id);
      return;
    }
    if (state.playing) return;
    final op = ++_op;
    await _waitForGuests(id);
    if (op != _op) return;
    final from = state.positionUs;
    final end = sync.duration?.inMicroseconds;
    await _setState(_playingFrom(id, end != null && from >= end ? 0 : from));
  }

  Future<void> pause() async {
    final id = state.trackId;
    if (id == null || !state.playing) return;
    _op++;
    await _setState(_pausedAt(id, position.inMicroseconds));
  }

  Future<void> togglePlay() => state.playing ? pause() : play();

  Future<void> seek(Duration to) async {
    final id = state.trackId;
    if (id == null) return;
    _op++;
    await _setState(state.playing
        ? _playingFrom(id, to.inMicroseconds)
        : _pausedAt(id, to.inMicroseconds));
  }

  Future<void> next({bool fromEnd = false}) async {
    final i = currentIndex;
    if (i < 0) return;
    if (i + 1 < playlist.length) {
      await playTrack(playlist[i + 1].id, autoplay: fromEnd || state.playing);
    } else if (fromEnd) {
      await _setState(_pausedAt(playlist[i].id, 0)); // End of the playlist.
    }
  }

  Future<void> previous() async {
    final i = currentIndex;
    if (i < 0) return;
    if (i == 0 || position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
    } else {
      await playTrack(playlist[i - 1].id, autoplay: state.playing);
    }
  }

  /// Waits until every guest has the song, or [readyTimeout] passes; a late
  /// guest catches up by itself once its download ends.
  Future<void> _waitForGuests(String id) async {
    final deadline = DateTime.now().add(readyTimeout);
    while (guests.any((g) => !g.ready.contains(id)) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _setState(PlayState s) async {
    state = s;
    _broadcast(encodeMessage('state', s.toJson()));
    notifyListeners();
    await sync.apply(s);
    notifyListeners();
  }

  Future<void> close() async {
    _op++;
    _beacon?.stop();
    _broadcast(encodeMessage('bye'));
    for (final g in [...guests]) {
      await g.socket.close();
    }
    guests.clear();
    await _server?.close(force: true);
    await _completedSub?.cancel();
    await sync.dispose();
    for (final p in _paths.values) {
      _deleteQuietly(p);
    }
  }

  void _deleteQuietly(String path) {
    File(path).delete().ignore();
  }
}
