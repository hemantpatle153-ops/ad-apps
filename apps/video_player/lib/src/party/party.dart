import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../player/system_channel.dart';
import 'clock.dart';
import 'discovery.dart';
import 'follower.dart';
import 'protocol.dart';

/// A watch party on the local network (same Wi-Fi or one phone's hotspot).
/// One phone hosts and streams its video; friends join and their players
/// follow the host's timeline. Anyone can play, pause or seek, chat and
/// send reactions. No internet or server is involved.
abstract class WatchParty extends ChangeNotifier {
  WatchParty(this.myName);

  final String myName;
  bool get isHost;

  /// Names of everyone in the party, this phone included.
  List<String> members = [];
  final List<PartyMessage> messages = [];

  /// Fires for every chat line and reaction, for the on-video overlay.
  final _incoming = StreamController<PartyMessage>.broadcast();
  Stream<PartyMessage> get incoming => _incoming.stream;

  /// Set when the party ended from the other side (host left, lost Wi-Fi).
  String? endedReason;

  Player? player;

  void attach(Player p) => player = p;

  Future<void> requestPlay();
  Future<void> requestPause();
  Future<void> requestSeek(Duration to);
  Future<void> requestRate(double rate);
  void sendChat(String text);
  void sendReaction(String emoji);
  Future<void> close();

  /// Adds a chat line or reaction and shows it on the video.
  @protected
  void received(PartyMessage m) => _received(m);

  void _received(PartyMessage m) {
    messages.add(m);
    if (messages.length > 200) messages.removeAt(0);
    _incoming.add(m);
    notifyListeners();
  }

  @override
  void dispose() {
    _incoming.close();
    super.dispose();
  }
}

class _Guest {
  _Guest(this.socket);

  final WebSocket socket;
  String name = 'Friend';

  void send(String message) {
    try {
      socket.add(message);
    } on Object {
      // Closed; the done handler removes it.
    }
  }
}

/// Runs on the phone whose video everyone watches.
class PartyHost extends WatchParty {
  PartyHost(super.myName, {required this.video, this.filePath});

  final PartyVideo video;

  /// File streamed to guests, when the video is on this phone.
  final String? filePath;

  @override
  bool get isHost => true;

  HttpServer? _server;
  Beacon? _beacon;
  List<String> addresses = [];
  final List<_Guest> _guests = [];
  PartyState state = PartyState.start;
  final _subs = <StreamSubscription>[];
  Timer? _watch;

  int get port => _server?.port ?? partyPort;
  JoinCode get joinCode => JoinCode(hosts: addresses, port: port, name: myName);
  int get guestCount => _guests.length;

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, partyPort);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen(_handle, onError: (_) {});
    addresses = await localAddresses();
    _beacon = await Beacon.start(name: myName, port: port, addresses: addresses);
    await SystemChannel.instance.holdNetwork(true);
    members = [myName];
    notifyListeners();
  }

  /// Re-reads this phone's addresses, e.g. after turning on the hotspot.
  Future<void> refreshAddresses() async {
    addresses = await localAddresses();
    _beacon?.stop();
    _beacon = await Beacon.start(name: myName, port: port, addresses: addresses);
    notifyListeners();
  }

  @override
  void attach(Player p) {
    super.attach(p);
    // The host's own player is the truth: whatever changes it (buttons,
    // gestures, the notification) is published to everyone.
    _subs.addAll([
      p.stream.playing.listen((_) => publish()),
      p.stream.buffering.listen((_) => publish()),
      p.stream.rate.listen((_) => publish()),
    ]);
    _watch = Timer.periodic(const Duration(milliseconds: 500), (_) => _checkJump());
    publish();
  }

  /// Notices seeks (and drift) by comparing the position with where it
  /// should be, and republishes every few seconds regardless.
  void _checkJump() {
    final p = player;
    if (p == null) return;
    final now = Clock.nowUs();
    final pos = p.state.position.inMicroseconds;
    final expected = state.positionAt(now);
    final heartbeat = now - state.anchorUs > 3000000;
    if ((pos - expected).abs() > 1200000 || heartbeat) publish();
  }

  void publish({Duration? at}) {
    final p = player;
    if (p == null) return;
    state = PartyState(
      playing: p.state.playing && !p.state.buffering,
      positionUs: (at ?? p.state.position).inMicroseconds,
      anchorUs: Clock.nowUs(),
      rate: p.state.rate,
    );
    _broadcast(encodeMessage('state', state.toJson()));
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.pingInterval = const Duration(seconds: 5);
      final g = _Guest(ws);
      _guests.add(g);
      ws.listen((data) => _onMessage(g, data),
          onDone: () => _drop(g), onError: (_) => _drop(g));
      return;
    }
    if (path == '/video' && filePath != null) {
      await _serveFile(req, File(filePath!));
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  /// Streams the video with HTTP range support, so guests can seek
  /// without downloading the whole file first.
  Future<void> _serveFile(HttpRequest req, File f) async {
    final res = req.response;
    try {
      final length = await f.length();
      res.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentType = ContentType('video', _subtype(f.path));
      final range = parseRange(req.headers.value(HttpHeaders.rangeHeader), length);
      if (range == null) {
        res.contentLength = length;
        if (req.method != 'HEAD') await res.addStream(f.openRead());
      } else {
        final (start, end) = range;
        res
          ..statusCode = HttpStatus.partialContent
          ..contentLength = end - start + 1;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
        if (req.method != 'HEAD') await res.addStream(f.openRead(start, end + 1));
      }
      await res.close();
    } on Object {
      // The guest seeked or left mid-transfer.
      try {
        await res.close();
      } on Object {
        // Already closed.
      }
    }
  }

  static String _subtype(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'mkv' => 'x-matroska',
      'webm' => 'webm',
      'avi' => 'x-msvideo',
      '3gp' => '3gpp',
      'mov' => 'quicktime',
      'ts' => 'mp2t',
      _ => 'mp4',
    };
  }

  void _onMessage(_Guest g, Object? data) {
    final m = decodeMessage(data);
    if (m == null) return;
    switch (m['t']) {
      case 'ping':
        // Answer first: any delay here becomes clock error.
        g.send(encodeMessage('pong', {'c': m['c'], 'h': Clock.nowUs()}));
      case 'hi':
        g.name = '${m['name'] ?? 'Friend'}';
        g.send(encodeMessage('welcome', {
          'video': video.toJson(),
          'state': state.toJson(),
        }));
        _sendMembers();
        _received(PartyMessage(from: g.name, text: 'joined'));
        _broadcast(encodeMessage('chat', {'from': g.name, 'text': 'joined'}), except: g);
      case 'req':
        _apply('${m['a']}', m['v']);
      case 'chat':
        final text = '${m['text'] ?? ''}'.trim();
        if (text.isEmpty) return;
        _received(PartyMessage(from: g.name, text: text));
        _broadcast(encodeMessage('chat', {'from': g.name, 'text': text}), except: g);
      case 'react':
        final e = '${m['e'] ?? ''}';
        if (e.isEmpty) return;
        _received(PartyMessage(from: g.name, text: e, emoji: true));
        _broadcast(encodeMessage('react', {'from': g.name, 'e': e}), except: g);
    }
  }

  Future<void> _apply(String action, Object? v) async {
    final p = player;
    if (p == null) return;
    switch (action) {
      case 'play':
        await p.play();
      case 'pause':
        await p.pause();
      case 'seek':
        if (v is num) {
          final to = Duration(microseconds: v.toInt());
          await p.seek(to);
          publish(at: to);
        }
      case 'rate':
        if (v is num) await p.setRate(v.toDouble());
    }
  }

  void _drop(_Guest g) {
    if (_guests.remove(g)) {
      _sendMembers();
      _received(PartyMessage(from: g.name, text: 'left'));
    }
  }

  void _sendMembers() {
    members = [myName, for (final g in _guests) g.name];
    _broadcast(encodeMessage('members', {'names': members}));
    notifyListeners();
  }

  void _broadcast(String message, {_Guest? except}) {
    for (final g in _guests) {
      if (g != except) g.send(message);
    }
  }

  @override
  Future<void> requestPlay() async => player?.play();

  @override
  Future<void> requestPause() async => player?.pause();

  @override
  Future<void> requestSeek(Duration to) async {
    await player?.seek(to);
    publish(at: to);
  }

  @override
  Future<void> requestRate(double rate) async => player?.setRate(rate);

  @override
  void sendChat(String text) {
    text = text.trim();
    if (text.isEmpty) return;
    _received(PartyMessage(from: myName, text: text));
    _broadcast(encodeMessage('chat', {'from': myName, 'text': text}));
  }

  @override
  void sendReaction(String emoji) {
    _received(PartyMessage(from: myName, text: emoji, emoji: true));
    _broadcast(encodeMessage('react', {'from': myName, 'e': emoji}));
  }

  @override
  Future<void> close() async {
    _watch?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _beacon?.stop();
    _broadcast(encodeMessage('bye'));
    for (final g in [..._guests]) {
      await g.socket.close();
    }
    _guests.clear();
    await _server?.close(force: true);
    await SystemChannel.instance.holdNetwork(false);
  }
}

enum GuestStatus { connecting, connected, failed, ended }

/// Runs on a friend's phone: follows the host's timeline.
class PartyGuest extends WatchParty {
  PartyGuest(super.myName, this.code);

  final JoinCode code;

  @override
  bool get isHost => false;

  GuestStatus status = GuestStatus.connecting;
  String? hostAddress;
  PartyVideo? video;
  PartyState state = PartyState.start;
  final ClockSync clock = ClockSync();
  WebSocket? _ws;
  Timer? _pinger, _sync;
  bool _closed = false;
  final _welcome = Completer<bool>();

  late final _follower = TimelineFollower(nowUs: hostNowUs);

  int hostNowUs() => Clock.nowUs() + clock.offsetUs;

  /// Where to stream the video from.
  String get videoUri =>
      video?.url ?? 'http://$hostAddress:${code.port}/video';

  /// Connects and waits for the host's welcome. False if no address answers.
  Future<bool> connect() async {
    await SystemChannel.instance.holdNetwork(true);
    for (final h in code.hosts) {
      if (_closed) return false;
      try {
        final ws = await WebSocket.connect('ws://$h:${code.port}/ws')
            .timeout(const Duration(seconds: 3));
        ws.pingInterval = const Duration(seconds: 5);
        hostAddress = h;
        _ws = ws;
        ws.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
        _send('hi', {'name': myName, 'v': partyProtocol});
        _startPinging();
        return await _welcome.future.timeout(const Duration(seconds: 6),
            onTimeout: () => false);
      } on Object {
        // Try the next address.
      }
    }
    status = GuestStatus.failed;
    notifyListeners();
    return false;
  }

  void _send(String type, [Map<String, Object?> body = const {}]) {
    try {
      _ws?.add(encodeMessage(type, body));
    } on Object {
      // Closed; _onClosed handles it.
    }
  }

  /// A burst of pings to learn the host's clock, then one every 2 s.
  void _startPinging() {
    var burst = 12;
    void ping() => _send('ping', {'c': Clock.nowUs()});
    _pinger = Timer.periodic(const Duration(milliseconds: 120), (t) {
      ping();
      if (--burst == 0) {
        t.cancel();
        _pinger = Timer.periodic(const Duration(seconds: 2), (_) => ping());
      }
    });
  }

  void _onMessage(Object? data) {
    final now = Clock.nowUs();
    final m = decodeMessage(data);
    if (m == null) return;
    switch (m['t']) {
      case 'pong':
        final c = m['c'], h = m['h'];
        if (c is int && h is int) clock.add(sentUs: c, hostUs: h, receivedUs: now);
      case 'welcome':
        video = PartyVideo.fromJson((m['video'] as Map).cast<String, Object?>());
        state = PartyState.fromJson((m['state'] as Map).cast<String, Object?>());
        status = GuestStatus.connected;
        if (!_welcome.isCompleted) _welcome.complete(true);
        notifyListeners();
      case 'state':
        state = PartyState.fromJson(m);
        _follower.reset();
        _syncNow();
      case 'members':
        members = [for (final n in (m['names'] as List? ?? const [])) '$n'];
        notifyListeners();
      case 'chat':
        _received(PartyMessage(from: '${m['from']}', text: '${m['text']}'));
      case 'react':
        _received(PartyMessage(from: '${m['from']}', text: '${m['e']}', emoji: true));
      case 'bye':
        _end('The host ended the watch party');
    }
  }

  @override
  void attach(Player p) {
    super.attach(p);
    _sync = Timer.periodic(const Duration(milliseconds: 500), (_) => _syncNow());
  }

  void _syncNow() {
    final p = player;
    if (p == null || !clock.hasEstimate || status != GuestStatus.connected) return;
    _follower.follow(p, state);
  }

  void _onClosed() {
    if (_closed) return;
    if (!_welcome.isCompleted) _welcome.complete(false);
    _end('Lost the connection to the host');
  }

  void _end(String reason) {
    if (status == GuestStatus.ended) return;
    status = GuestStatus.ended;
    endedReason = reason;
    _sync?.cancel();
    player?.pause();
    notifyListeners();
  }

  @override
  Future<void> requestPlay() async => _send('req', {'a': 'play'});

  @override
  Future<void> requestPause() async => _send('req', {'a': 'pause'});

  @override
  Future<void> requestSeek(Duration to) async =>
      _send('req', {'a': 'seek', 'v': to.inMicroseconds});

  @override
  Future<void> requestRate(double rate) async => _send('req', {'a': 'rate', 'v': rate});

  @override
  void sendChat(String text) {
    text = text.trim();
    if (text.isEmpty) return;
    _received(PartyMessage(from: myName, text: text));
    _send('chat', {'text': text});
  }

  @override
  void sendReaction(String emoji) {
    _received(PartyMessage(from: myName, text: emoji, emoji: true));
    _send('react', {'e': emoji});
  }

  @override
  Future<void> close() async {
    _closed = true;
    _pinger?.cancel();
    _sync?.cancel();
    await _ws?.close();
    await SystemChannel.instance.holdNetwork(false);
  }
}
