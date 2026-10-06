import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../main.dart' show appName;
import '../engine.dart';
import '../online/backend.dart';
import '../online/firebase_backend.dart';
import '../online/session.dart';
import '../sfx.dart';
import '../store.dart';
import 'game_screen.dart';
import 'kit.dart';
import 'pieces.dart';

/// Makes the room server. Tests swap in a [MemoryBackend].
RoomBackend Function() roomBackend = FirebaseBackend.new;

/// Bool for whether online play can work in this build.
bool Function() onlineAvailable = () => FirebaseSetup.configured;

/// Create a room and share its code, or join a friend's room by code.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key, required this.store, required this.sfx});

  final LudoStore store;
  final LudoSfx sfx;

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  LudoStore get store => widget.store;

  late final _name = TextEditingController(text: store.playerName);
  final _code = TextEditingController();
  int _size = 4;
  bool _quick = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _player {
    final t = _name.text.trim();
    return t.isEmpty ? 'Player' : t;
  }

  Future<void> _run(
      Future<(RoomBackend, String, int)> Function(RoomBackend b) task) async {
    widget.sfx.play(LudoSound.tap);
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_name.text.trim().isNotEmpty) store.playerName = _name.text.trim();
    try {
      final b = roomBackend();
      await b.connect();
      final (backend, code, seat) = await task(b);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LobbyScreen(
          store: store,
          sfx: widget.sfx,
          backend: backend,
          code: code,
          mySeat: seat,
        ),
      ));
    } on RoomException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = const RoomException(RoomError.offline).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _create() => _run((b) async {
        final code = await b.createRoom(
          name: _player,
          size: _size,
          rules: store.rules.copyWith(tokens: _quick ? 2 : 4),
        );
        return (b, code, 0);
      });

  void _join() {
    final code = cleanCode(_code.text);
    if (code.length != 6) {
      setState(() => _error = 'Room codes have 6 letters and numbers.');
      return;
    }
    _run((b) async => (b, code, await b.joinRoom(code, _player)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = store.theme;
    if (!onlineAvailable()) {
      return LudoPage(theme: theme, title: 'Play with Friends', children: [
        const SizedBox(height: 24),
        LudoPanel(
          theme: theme,
          child: const Column(
            children: [
              Icon(Icons.cloud_off_rounded, size: 56),
              SizedBox(height: 12),
              Text('Online rooms are coming soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              SizedBox(height: 6),
              Text(
                'This version plays offline only. Try Pass & Play to play '
                'with friends on one phone.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ]);
    }
    return LudoPage(
      theme: theme,
      title: 'Play with Friends',
      children: [
        const LudoHeading('Your name'),
        LudoPanel(
          theme: theme,
          child: TextField(
            controller: _name,
            maxLength: 14,
            style: TextStyle(color: theme.onPanel),
            decoration: const InputDecoration(
              counterText: '',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ),
        ),
        const LudoHeading('Join a room'),
        LudoPanel(
          theme: theme,
          child: Column(
            children: [
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                maxLength: 7,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: theme.onPanel,
                    fontSize: 26,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w900),
                decoration: const InputDecoration(
                  hintText: 'CODE',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _join(),
              ),
              const SizedBox(height: 12),
              ChunkyButton(
                label: 'Join',
                icon: Icons.login_rounded,
                color: theme.colors[3],
                onPressed: _busy ? null : _join,
              ),
            ],
          ),
        ),
        const LudoHeading('Or create a room'),
        LudoPanel(
          theme: theme,
          child: Column(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('2 players')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {_size},
                onSelectionChanged: (s) => setState(() => _size = s.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quick game'),
                subtitle: const Text('2 pieces each'),
                value: _quick,
                onChanged: (v) => setState(() => _quick = v),
              ),
              ChunkyButton(
                label: 'Create room',
                icon: Icons.add_rounded,
                onPressed: _busy ? null : _create,
              ),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child:
                Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: LudoPanel(
              theme: theme,
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFD32F2F)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Voice chat turns on when the game starts. Calls go straight '
          'between phones and are encrypted.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}

/// Waiting room: shows the code, who has joined, and starts the game.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.store,
    required this.sfx,
    required this.backend,
    required this.code,
    required this.mySeat,
  });

  final LudoStore store;
  final LudoSfx sfx;
  final RoomBackend backend;
  final String code;
  final int mySeat;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription<RoomState?>? _sub;
  RoomState? _room;
  bool _gone = false;
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.backend.watchRoom(widget.code).listen((r) {
      if (!mounted) return;
      setState(() {
        _room = r;
        _gone = r == null;
      });
      if (r != null && r.started && !_launched) _launch(r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _launch(RoomState r) {
    _launched = true;
    _sub?.cancel();
    final session =
        OnlineSession(backend: widget.backend, room: r, mySeat: widget.mySeat);
    final engine = LudoEngine(players: r.players(), rules: r.rules);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LudoGameScreen(
        engine: engine,
        store: widget.store,
        sfx: widget.sfx,
        link: OnlineLink(widget.backend, r.code, r, widget.mySeat),
        me: r.playerOf(widget.mySeat),
        session: session,
      ),
    ));
  }

  Future<void> _leave() async {
    await _sub?.cancel();
    await widget.backend.leave(widget.code, widget.mySeat).catchError((_) {});
  }

  void _share() {
    SharePlus.instance.share(ShareParams(
      text: 'Play Ludo with me on $appName! Open Play with Friends and '
          'join room ${widget.code}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.store.theme;
    final r = _room;
    final host = r?.host == widget.mySeat;
    final canStart = host && (r?.seats.length ?? 0) >= 2;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_launched) _leave();
      },
      child: LudoPage(
        theme: theme,
        title: 'Room',
        children: [
          const SizedBox(height: 8),
          LudoPanel(
            theme: theme,
            child: Column(
              children: [
                const Text('Share this code with friends'),
                const SizedBox(height: 6),
                SelectableText(
                  widget.code,
                  style: TextStyle(
                      color: theme.onPanel,
                      fontSize: 40,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.code));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Code copied')));
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          LudoHeading(r == null
              ? 'Connecting…'
              : 'Players (${r.seats.length} of ${r.size})'),
          if (_gone)
            LudoPanel(theme: theme, child: const Text('This room was closed.'))
          else if (r != null)
            LudoPanel(
              theme: theme,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var s = 0; s < r.size; s++)
                    ListTile(
                      leading: PieceIcon(
                          color: theme.colors[RoomState.colorsFor(r.size)[s]],
                          size: 34),
                      title: Text(
                        r.seats[s] == null
                            ? 'Waiting…'
                            : s == widget.mySeat
                                ? '${r.seats[s]!.name} (you)'
                                : r.seats[s]!.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: r.seats[s] == null
                                ? theme.onPanel.withValues(alpha: 0.5)
                                : theme.onPanel),
                      ),
                      trailing: r.seats[s] == null
                          ? null
                          : Icon(
                              r.seats[s]!.online
                                  ? Icons.check_circle_rounded
                                  : Icons.wifi_off_rounded,
                              color: r.seats[s]!.online
                                  ? const Color(0xFF00C853)
                                  : Colors.grey),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          if (r != null && host)
            ChunkyButton(
              label: canStart ? 'Start game' : 'Waiting for friends',
              icon: Icons.play_arrow_rounded,
              onPressed:
                  canStart ? () => widget.backend.startGame(widget.code) : null,
            )
          else if (r != null)
            const Text(
              'Waiting for the host to start…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
        ],
      ),
    );
  }
}
