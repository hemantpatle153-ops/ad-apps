import 'dart:async';
import 'dart:math';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../../ui/confetti.dart';
import '../../ui/dice.dart';
import '../bot.dart';
import '../engine.dart';
import '../match.dart';
import '../online/session.dart';
import '../online/voice.dart';
import '../sfx.dart';
import '../store.dart';
import '../themes.dart';
import 'board_painter.dart';
import 'geometry.dart';
import 'kit.dart';
import 'pieces.dart';

/// Screen corners, clockwise from top-left (the order of the yards).
enum _Corner { topLeft, topRight, bottomRight, bottomLeft }

class LudoGameScreen extends StatefulWidget {
  const LudoGameScreen({
    super.key,
    required this.engine,
    required this.store,
    required this.sfx,
    required this.link,
    this.gameId,
    this.me,
    this.session,
  });

  final LudoEngine engine;
  final LudoStore store;
  final LudoSfx sfx;
  final MatchLink link;

  /// Save slot for a game on this phone; null online.
  final String? gameId;

  /// The player this phone belongs to (vs-computer and online). The board
  /// turns so that player's colour sits bottom-left.
  final int? me;
  final OnlineSession? session;

  @override
  State<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends State<LudoGameScreen>
    with TickerProviderStateMixin {
  LudoEngine get g => widget.engine;
  LudoStore get store => widget.store;
  LudoSfx get sfx => widget.sfx;
  MatchLink get link => widget.link;
  OnlineSession? get session => widget.session;

  /// How long a person has for each step of a turn online before the
  /// computer plays it for them.
  static const _turnLimit = Duration(seconds: 25);

  late final int _view;
  late final PieceLayer _pieces;
  late final AnimationController _move = AnimationController(vsync: this);
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();
  late final List<GlobalKey<DiceViewState>> _dice;
  late final List<int> _shownRoll;
  late final int _tokenCount = g.rules.tokens;

  StreamSubscription<(int, GameAction)>? _sub;
  final _queue = <(int, GameAction)>[];
  bool _pumping = false;

  /// Actions applied so far; the next one must have this index.
  int _applied = 0;

  /// Index we already sent an action for, so nothing is sent twice.
  int _sent = -1;

  /// Movable tokens while this phone waits for a tap.
  List<int> _choices = const [];

  /// The player whose dice is shown as active.
  int? _actor;
  bool _rolling = false;
  String? _toast;
  int _toastId = 0;
  bool _celebrate = false;
  bool _finished = false;
  Timer? _autoTimer;
  Timer? _clock;
  DateTime? _deadline;

  int get _me => widget.me ?? 0;

  @override
  void initState() {
    super.initState();
    final viewColor = g.players[_me].color;
    _view = (3 - viewColor) % 4;
    _pieces = PieceLayer(
      [
        for (final p in g.players)
          for (var t = 0; t < _tokenCount; t++)
            widget.store.theme.colors[p.color]
      ],
      [
        for (var p = 0; p < g.players.length; p++)
          for (var t = 0; t < _tokenCount; t++) _spot(p, t, g.tokens[p][t])
      ],
    );
    _dice = List.generate(g.players.length, (_) => GlobalKey<DiceViewState>());
    _shownRoll = List.filled(g.players.length, 6);
    _pulse.addListener(() => _pieces.setPulse(_pulse.value));
    _sub = link.actions.listen((a) {
      _queue.add(a);
      _pump();
    });
    final s = session;
    if (s != null) {
      s.seats.addListener(_onSeats);
      s.voice.error.addListener(_onVoiceError);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _drive());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _clock?.cancel();
    _sub?.cancel();
    link.close();
    session?.seats.removeListener(_onSeats);
    session?.voice.error.removeListener(_onVoiceError);
    _move.dispose();
    _pulse.dispose();
    _pieces.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- geometry

  int _index(int p, int t) => p * _tokenCount + t;

  Offset _spot(int p, int t, int progress) => Grid.rotate(
      Grid.tokenSpot(g.players[p].color, progress, t, _tokenCount), _view);

  _Corner _cornerOf(int player) =>
      _Corner.values[(g.players[player].color + _view) % 4];

  int? _playerAt(_Corner c) {
    for (var p = 0; p < g.players.length; p++) {
      if (_cornerOf(p) == c) return p;
    }
    return null;
  }

  // ------------------------------------------------------------- the flow

  bool _controls(int p) => link.controls(g, p);

  /// A person on this phone acts for [p] (not a computer player).
  bool _human(int p) => _controls(p) && !g.players[p].isBot;

  Future<void> _send(GameAction a) async {
    if (_sent == _applied || _finished) return;
    _sent = _applied;
    _stopClock();
    try {
      await link.send(_applied, a);
    } catch (_) {
      _sent = -1;
      if (mounted) _say('Connection lost. Retrying…');
      _autoTimer = Timer(const Duration(seconds: 2), _drive);
    }
  }

  void _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty && mounted) {
        final (i, a) = _queue.removeAt(0);
        if (i < _applied) continue;
        if (i > _applied) {
          // Out of order (should not happen); wait for the gap to fill.
          _queue.insert(0, (i, a));
          _queue.sort((x, y) => x.$1.compareTo(y.$1));
          break;
        }
        _applied++;
        if (!a.validFor(g)) continue;
        _autoTimer?.cancel();
        _stopClock();
        final ok = switch (a) {
          RollAction(:final value) => await _playRoll(value),
          MoveAction(:final token) => await _playMove(token),
        };
        if (!ok) return;
      }
    } finally {
      _pumping = false;
    }
    if (mounted && _queue.isEmpty) {
      final id = widget.gameId;
      if (id != null && !_finished) unawaited(store.save(id, g));
      _drive();
    }
  }

  /// Decides what should happen next and who does it.
  void _drive() {
    _autoTimer?.cancel();
    if (!mounted || _finished || g.isOver || _pumping) return;
    final p = g.current;
    final fast = store.fastMoves;
    setState(() {
      _actor = p;
      _choices = g.phase == Phase.move && _human(p)
          ? g.movableFor(p, g.lastRoll)
          : const [];
    });
    _pieces.setGlow([for (final t in _choices) _index(p, t)]);

    if (_controls(p)) {
      if (g.players[p].isBot) {
        _autoTimer = Timer(Duration(milliseconds: fast ? 350 : 700), _auto);
        return;
      }
      if (g.phase == Phase.move) {
        final opts = g.movableFor(p, g.lastRoll);
        final spots = {for (final t in opts) g.tokens[p][t]};
        // One real choice: move it for the player, like Ludo King does.
        if (spots.length == 1) {
          _autoTimer = Timer(const Duration(milliseconds: 280),
              () => _send(MoveAction(p, opts.first)));
          return;
        }
      }
      if (link.online) _startClock(_turnLimit);
      return;
    }
    // Someone else's turn online: the host steps in for a missing player.
    final s = session;
    if (s != null && s.isHost) {
      final seat = s.room.seatOf(p);
      final away = !s.isOnline(seat);
      _autoTimer = Timer(
          away
              ? const Duration(seconds: 3)
              : _turnLimit + const Duration(seconds: 5),
          _auto);
    }
  }

  /// Plays the current step with the computer's choice.
  void _auto() {
    if (!mounted || _finished || g.isOver || _pumping) return;
    final p = g.current;
    if (g.phase == Phase.roll) {
      _send(RollAction(p, g.rollDie()));
    } else {
      final opts = g.movableFor(p, g.lastRoll);
      if (opts.isNotEmpty) _send(MoveAction(p, chooseMove(g, opts)));
    }
  }

  void _startClock(Duration d) {
    _deadline = DateTime.now().add(d);
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_deadline!)) {
        _stopClock();
        _auto();
      } else {
        setState(() {});
      }
    });
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
    _deadline = null;
  }

  void _tapDice() {
    final p = g.current;
    if (_pumping || g.phase != Phase.roll || !_human(p)) return;
    _send(RollAction(p, g.rollDie()));
  }

  void _tapBoard(Offset local, double side) {
    if (_choices.isEmpty || _pumping) return;
    final hit = _pieces.hit(local / (side / Grid.size));
    if (hit == null) return;
    final p = hit ~/ _tokenCount, t = hit % _tokenCount;
    if (p != g.current || !_choices.contains(t)) return;
    sfx.play(LudoSound.tap);
    setState(() => _choices = const []);
    _pieces.setGlow(const []);
    _send(MoveAction(p, t));
  }

  // ------------------------------------------------------------ animation

  Duration get _hop => Duration(milliseconds: store.fastMoves ? 110 : 190);

  Future<bool> _animate(Duration d, void Function(double t) frame) async {
    _move.duration = d;
    void tick() => frame(_move.value);
    _move.addListener(tick);
    try {
      await _move.forward(from: 0).orCancel;
    } on TickerCanceled {
      return false;
    } finally {
      _move.removeListener(tick);
    }
    if (!mounted) return false;
    frame(1);
    return true;
  }

  Future<bool> _pause(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    return mounted;
  }

  void _say(String text) {
    final id = ++_toastId;
    setState(() => _toast = text);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && id == _toastId) setState(() => _toast = null);
    });
  }

  String _who(int p) =>
      _human(p) && !link.online && g.players.where((x) => !x.isBot).length == 1
          ? 'You'
          : g.players[p].name;

  Future<bool> _playRoll(int value) async {
    final p = g.current;
    setState(() {
      _actor = p;
      _rolling = true;
      _choices = const [];
    });
    _pieces.setGlow(const []);
    sfx.play(LudoSound.dice);
    sfx.buzz();
    await _dice[p].currentState?.roll(value);
    if (!mounted) return false;
    setState(() {
      _shownRoll[p] = value;
      _rolling = false;
    });
    final r = g.roll(value);
    if (r.threeSixes) {
      _say('Three sixes! Turn lost');
      return _pause(900);
    }
    if (value == 6) sfx.play(LudoSound.six);
    if (r.movable.isEmpty) {
      if (value == 6) {
        _say('Roll again');
        return _pause(400);
      }
      return _pause(g.players[p].isBot || !_human(p) ? 450 : 650);
    }
    return true;
  }

  Future<bool> _playMove(int token) async {
    final p = g.current;
    final m = g.move(token);
    final i = _index(p, token);
    setState(() => _choices = const []);
    _pieces.setGlow(const []);

    if (m.from == Track.yard) {
      sfx.play(LudoSound.out);
      final a = _pieces.pos[i], b = _spot(p, token, 0);
      final ok = await _animate(const Duration(milliseconds: 260), (t) {
        _pieces.move(i, Offset.lerp(a, b, Curves.easeOut.transform(t))!,
            lift: sin(pi * t) * 0.5);
      });
      if (!ok) return false;
    } else {
      var at = _pieces.pos[i];
      for (final step in m.steps) {
        final a = at, b = _spot(p, token, step);
        final ok = await _animate(_hop, (t) {
          _pieces.move(i, Offset.lerp(a, b, t)!, lift: sin(pi * t) * 0.32);
        });
        if (!ok) return false;
        sfx.play(LudoSound.step);
        at = b;
      }
    }
    _pieces.move(i, _spot(p, token, m.to));

    for (final c in m.captures) {
      sfx.play(LudoSound.capture);
      sfx.buzz(strong: true);
      _say(c.player == _me && link.online
          ? '${g.players[p].name} cut your piece!'
          : '${_who(p)} cut ${g.players[c.player].name}!');
      if (!await _sendHome(c)) return false;
    }
    if (m.finishedToken) {
      sfx.play(LudoSound.home);
      if (!m.finishedPlayer) _say('Home! Roll again');
    }
    if (m.finishedPlayer && !m.gameOver) {
      final place = g.finishOrder.length;
      _say('${_who(p)} finished ${_ordinal(place)}!');
      if (!await _pause(900)) return false;
    }
    if (m.gameOver) {
      await _finish();
      return false;
    }
    if (m.extraTurn && m.captures.isEmpty && !m.finishedToken) {
      if (!await _pause(150)) return false;
    }
    return true;
  }

  /// Slides a captured piece back along the track to its yard.
  Future<bool> _sendHome(Capture c) async {
    final i = _index(c.player, c.token);
    final path = [
      for (var s = c.from; s >= 0; s--) _spot(c.player, c.token, s),
      _spot(c.player, c.token, Track.yard),
    ];
    final ms = min(900, 200 + path.length * 22);
    return _animate(Duration(milliseconds: ms), (t) {
      final e = Curves.easeIn.transform(t) * (path.length - 1);
      final k = e.floor().clamp(0, path.length - 2);
      _pieces.move(i, Offset.lerp(path[k], path[k + 1], e - k)!,
          lift: t < 1 ? 0.15 : 0);
    });
  }

  static String _ordinal(int n) =>
      const ['1st', '2nd', '3rd', '4th'][(n - 1).clamp(0, 3)];

  Future<void> _finish() async {
    _finished = true;
    _autoTimer?.cancel();
    _stopClock();
    setState(() {
      _celebrate = true;
      _actor = null;
    });
    sfx.play(LudoSound.win);
    sfx.buzz(strong: true);
    final id = widget.gameId;
    if (id != null) await store.deleteSaved(id);
    final vsBot = g.players.any((p) => p.isBot);
    await store.recordGame(g,
        me: vsBot || link.online ? _me : null, online: link.online);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    final again = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WinDialog(
        engine: g,
        theme: store.theme,
        me: vsBot || link.online ? _me : null,
        canReplay: !link.online,
      ),
    );
    // A finished game is the natural break for a full-screen ad.
    await AdService.instance.maybeShowInterstitial();
    if (!mounted) return;
    if (again == true) {
      final next = LudoEngine(players: g.players, rules: g.rules);
      final id = LudoStore.newGameId();
      await store.save(id, next);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LudoGameScreen(
          engine: next,
          store: store,
          sfx: sfx,
          link: LocalLink(),
          gameId: id,
          me: widget.me,
        ),
      ));
    } else {
      await session?.close();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _confirmLeave() async {
    final online = link.online;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the game?'),
        content: Text(online
            ? 'Your friends keep playing and the computer moves your pieces.'
            : 'Your game is saved. Continue it any time from the Ludo menu.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    _finished = true;
    _autoTimer?.cancel();
    _stopClock();
    final id = widget.gameId;
    if (id != null && !g.isOver) await store.save(id, g);
    await session?.close();
    if (mounted) Navigator.of(context).pop();
  }

  void _onSeats() {
    if (mounted) setState(() {});
    // Someone dropped or came back: re-check who acts.
    if (!_pumping && _sent != _applied) _drive();
  }

  void _onVoiceError() {
    final e = session?.voice.error.value;
    if (e != null && mounted) _say(e);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = store.theme;
    return PopScope(
      canPop: _finished && g.isOver,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: LudoBackground(
          theme: theme,
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    _topBar(theme),
                    Expanded(
                      child: LayoutBuilder(builder: (context, box) {
                        const panelRow = 96.0;
                        final side = min(box.maxWidth - 12,
                            box.maxHeight - 2 * panelRow - 34);
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _panelRow(
                                  _Corner.topLeft, _Corner.topRight, theme,
                                  top: true),
                              _board(theme, side),
                              _panelRow(_Corner.bottomLeft, _Corner.bottomRight,
                                  theme,
                                  top: false),
                              _hint(theme),
                            ],
                          ),
                        );
                      }),
                    ),
                    const BannerAdSlot(),
                  ],
                ),
              ),
              if (_celebrate)
                Positioned.fill(
                  child: Confetti(colors: [
                    ...theme.colors,
                    theme.accent,
                    Colors.white,
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mute (block) or report another player in an online room.
  Future<void> _playerSheet(int seat, String name) async {
    final s = session!;
    final who = name.isEmpty ? 'this player' : name;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ValueListenableBuilder<Set<int>>(
          valueListenable: s.voice.blocked,
          builder: (_, blocked, __) {
            final isBlocked = blocked.contains(seat);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                title: Text(who,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              ListTile(
                leading: Icon(isBlocked
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded),
                title: Text(isBlocked ? 'Unmute $who' : 'Mute $who'),
                subtitle: Text(isBlocked
                    ? 'Hear each other again'
                    : 'You stop hearing each other'),
                onTap: () => Navigator.pop(ctx, isBlocked ? 'unmute' : 'mute'),
              ),
              ListTile(
                leading: const Icon(Icons.flag_rounded, color: Colors.red),
                title: Text('Report $who'),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
            ]);
          },
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'mute':
        await s.voice.block(seat);
        _say('$who is muted');
      case 'unmute':
        s.voice.unblock(seat);
      case 'report':
        await _report(seat, who);
    }
  }

  static const _reasons = [
    'Abusive language',
    'Harassment or threats',
    'Offensive name',
    'Something else',
  ];

  Future<void> _report(int seat, String who) async {
    final s = session!;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Report $who'),
        children: [
          for (final r in _reasons)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(r),
              ),
            ),
        ],
      ),
    );
    if (!mounted || reason == null) return;
    await s.voice.block(seat);
    try {
      await s.backend.report(s.code, seat: seat, name: who, reason: reason);
      if (mounted) _say('Thanks. $who is reported and muted');
    } catch (_) {
      if (mounted) _say('Could not send the report. $who is muted');
    }
  }

  Widget _topBar(LudoTheme theme) {
    const fg = Colors.white;
    final s = session;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: fg),
            tooltip: 'Leave game',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              s != null ? 'Room ${s.code}' : 'Ludo',
              style: const TextStyle(
                  color: fg, fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (s != null)
            ValueListenableBuilder<bool>(
              valueListenable: s.voice.joined,
              builder: (_, joined, __) => !joined
                  ? TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: fg),
                      icon: const Icon(Icons.mic_none_rounded),
                      label: const Text('Voice'),
                      onPressed: s.voice.start,
                    )
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: s.voice.muted,
                        builder: (_, muted, __) => IconButton(
                          icon: Icon(
                              muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                              color: muted ? const Color(0xFFFF8A80) : fg),
                          tooltip: muted ? 'Unmute' : 'Mute',
                          onPressed: s.voice.toggleMute,
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: s.voice.speaker,
                        builder: (_, on, __) => IconButton(
                          icon: Icon(
                              on
                                  ? Icons.volume_up_rounded
                                  : Icons.phone_in_talk,
                              color: fg),
                          tooltip: on ? 'Use earpiece' : 'Use speaker',
                          onPressed: s.voice.toggleSpeaker,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.call_end_rounded,
                            color: Color(0xFFFF8A80)),
                        tooltip: 'Leave voice',
                        onPressed: s.voice.stop,
                      ),
                    ]),
            )
          else
            IconButton(
              icon: Icon(
                  store.sound
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: fg),
              tooltip: 'Sound',
              onPressed: () => setState(() => store.sound = !store.sound),
            ),
        ],
      ),
    );
  }

  Widget _panelRow(_Corner left, _Corner right, LudoTheme theme,
      {required bool top}) {
    final l = _playerAt(left), r = _playerAt(right);
    return SizedBox(
      height: 96,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          crossAxisAlignment:
              top ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: top ? Alignment.bottomLeft : Alignment.topLeft,
                child: l == null ? null : _panel(l, theme, mirrored: false),
              ),
            ),
            Expanded(
              child: Align(
                alignment: top ? Alignment.bottomRight : Alignment.topRight,
                child: r == null ? null : _panel(r, theme, mirrored: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(int i, LudoTheme theme, {required bool mirrored}) {
    final p = g.players[i];
    final color = theme.colors[p.color];
    final active = i == (_actor ?? g.current) && !g.isOver;
    final canRoll = active &&
        !_pumping &&
        !_rolling &&
        g.phase == Phase.roll &&
        _human(i) &&
        _sent != _applied;
    final done = g.hasFinished(i);
    final s = session;
    final seat = s?.room.seatOf(i);
    final away = s != null && seat != null && !s.isOnline(seat);

    final avatar = SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: s != null && seat != null && seat != s.mySeat && !p.isBot
                    ? () => _playerSheet(seat, p.name)
                    : null,
                child: _Avatar(
                  color: color,
                  active: active,
                  progress: _deadline != null && active
                      ? _deadline!.difference(DateTime.now()).inMilliseconds /
                          _turnLimit.inMilliseconds
                      : null,
                  child: p.isBot
                      ? const Icon(Icons.smart_toy_rounded,
                          color: Colors.white, size: 22)
                      : Text(
                          p.name.isEmpty
                              ? '?'
                              : p.name.characters.first.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900),
                        ),
                ),
              ),
              if (s != null && seat != null && seat != s.mySeat && !p.isBot)
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: _VoiceDot(voice: s.voice, seat: seat, away: away),
                ),
              if (done)
                Positioned(
                  right: -6,
                  top: -6,
                  child: _Badge(
                      text: _ordinal(g.finishOrder.indexOf(i) + 1),
                      color: theme.accent),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            away ? '${p.name} (away)' : _who(i),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: active ? 1 : 0.8),
              fontWeight: FontWeight.w800,
              fontSize: 12,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
            ),
          ),
        ],
      ),
    );

    final dice = AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: active ? 1 : 0.35,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: theme.panel.withValues(alpha: active ? 0.95 : 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active ? color : Colors.transparent, width: 2.5),
        ),
        child: DiceView(
          key: _dice[i],
          value: _shownRoll[i],
          color: color,
          size: 44,
          enabled: canRoll,
          dim: !active,
          onTap: _tapDice,
        ),
      ),
    );

    final children = [avatar, const SizedBox(width: 6), dice];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: mirrored ? children.reversed.toList() : children,
    );
  }

  /// One line telling the person on this phone what to do.
  Widget _hint(LudoTheme theme) {
    final p = g.current;
    String? text;
    if (!_finished && !g.isOver && !_pumping && _human(p)) {
      final who =
          _who(p) == 'You' || link.online ? 'Your' : "${g.players[p].name}'s";
      if (_choices.isNotEmpty) {
        text = 'Tap a piece to move ${g.lastRoll}';
      } else if (g.phase == Phase.roll && _sent != _applied) {
        text = '$who turn · tap the dice';
      }
    }
    return SizedBox(
      height: 34,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: text == null
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(text),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(text,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ),
      ),
    );
  }

  Widget _board(LudoTheme theme, double side) {
    final active = {for (final p in g.players) p.color};
    return SizedBox.square(
      dimension: side,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _tapBoard(d.localPosition, side),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(side / 24),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black45,
                        blurRadius: 20,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: LudoBoardPainter(theme,
                        view: _view, activeColors: active),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: PiecesPainter(_pieces)),
            ),
            Align(
              alignment: const Alignment(0, -0.05),
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale:
                        CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: _toast == null
                      ? const SizedBox.shrink()
                      : Container(
                          key: ValueKey(_toastId),
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            _toast!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round player badge with a coloured ring; the ring drains as a turn
/// timer online.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.color,
    required this.active,
    required this.child,
    this.progress,
  });

  final Color color;
  final bool active;
  final Widget child;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (active)
            BoxShadow(
                color: color.withValues(alpha: 0.8),
                blurRadius: 16,
                spreadRadius: 2),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                colors: [
                  Color.lerp(color, Colors.white, 0.35)!,
                  color,
                  Color.lerp(color, Colors.black, 0.25)!
                ],
              ),
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            alignment: Alignment.center,
            child: child,
          ),
          if (progress != null)
            SizedBox.square(
              dimension: 56,
              child: CircularProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                strokeWidth: 3.5,
                color: progress! < 0.3 ? const Color(0xFFFF5252) : Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.w900)),
      );
}

/// Small mic dot: green when you can hear that player.
class _VoiceDot extends StatelessWidget {
  const _VoiceDot(
      {required this.voice, required this.seat, required this.away});

  final VoiceChat voice;
  final int seat;
  final bool away;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([voice.peers, voice.joined, voice.blocked]),
      builder: (_, __) {
        if (!voice.joined.value && !voice.blocked.value.contains(seat)) {
          return const SizedBox.shrink();
        }
        final st = voice.peers.value[seat];
        final (color, icon) = voice.blocked.value.contains(seat)
            ? (const Color(0xFFFF5252), Icons.volume_off_rounded)
            : away
                ? (Colors.grey, Icons.wifi_off_rounded)
                : switch (st) {
                    PeerVoice.connected => (
                        const Color(0xFF00C853),
                        Icons.mic_rounded
                      ),
                    PeerVoice.failed => (
                        const Color(0xFFFF5252),
                        Icons.mic_off_rounded
                      ),
                    _ => (Colors.blueGrey, Icons.more_horiz_rounded),
                  };
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Icon(icon, size: 12, color: Colors.white),
        );
      },
    );
  }
}

class _WinDialog extends StatelessWidget {
  const _WinDialog({
    required this.engine,
    required this.theme,
    required this.me,
    required this.canReplay,
  });

  final LudoEngine engine;
  final LudoTheme theme;
  final int? me;
  final bool canReplay;

  @override
  Widget build(BuildContext context) {
    final g = engine;
    final w = g.winner!;
    final title = me == null
        ? '${g.players[w].name} wins!'
        : w == me
            ? 'You win!'
            : '${g.players[w].name} wins';
    const medals = ['🥇', '🥈', '🥉', '4th'];
    final order = g.standings;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              me != null && w != me
                  ? Icons.sentiment_satisfied_rounded
                  : Icons.emoji_events_rounded,
              size: 72,
              color: const Color(0xFFFFB300),
            ),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (var k = 0; k < order.length; k++)
              ListTile(
                dense: true,
                leading: PieceIcon(
                    color: theme.colors[g.players[order[k]].color], size: 30),
                title: Text(g.players[order[k]].name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${g.tokens[order[k]].where((t) => t == Track.home).length}'
                    ' of ${g.rules.tokens} home · '
                    '${g.captures[order[k]]} cuts'),
                trailing: Text(medals[k], style: const TextStyle(fontSize: 22)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Home'),
                  ),
                ),
                if (canReplay) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Play again'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
