import 'dart:async';
import 'dart:math';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../game/board.dart';
import '../game/engine.dart';
import '../game/store.dart';
import '../game/themes.dart';
import 'board_painter.dart';
import 'confetti.dart';
import 'dice.dart';
import 'geometry.dart';
import 'tokens.dart';
import 'widgets.dart';

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

/// Seats go clockwise from the bottom-left, like a Ludo board.
const _seats = {
  1: [_Corner.bottomLeft],
  2: [_Corner.bottomLeft, _Corner.topRight],
  3: [_Corner.bottomLeft, _Corner.topLeft, _Corner.topRight],
  4: [
    _Corner.bottomLeft,
    _Corner.topLeft,
    _Corner.topRight,
    _Corner.bottomRight
  ],
};

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.engine,
    required this.store,
    required this.sfx,
  });

  final GameEngine engine;
  final Store store;
  final Sfx sfx;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  GameEngine get g => widget.engine;
  Store get store => widget.store;
  Sfx get sfx => widget.sfx;

  late final TokenLayer _tokens;
  late final AnimationController _move = AnimationController(vsync: this);
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();
  late final List<GlobalKey<DiceViewState>> _dice;
  late final List<int> _lastRoll;

  bool _busy = false;

  /// The player whose move is animating; the engine has already moved on.
  int? _actor;
  String? _toast;
  int _toastId = 0;
  bool _celebrate = false;
  Timer? _botTimer;

  int get _shown => _actor ?? g.current;

  @override
  void initState() {
    super.initState();
    final n = g.players.length;
    _tokens = TokenLayer(
      [for (final p in g.players) p.color],
      [for (final pos in g.positions) unitCenter(pos)],
    );
    for (var i = 0; i < n; i++) {
      _tokens.waiting[i] = g.positions[i] == 0;
    }
    _dice = List.generate(n, (_) => GlobalKey<DiceViewState>());
    _lastRoll = List.filled(n, 6);
    _pulse.addListener(
        () => _tokens.setPulse(_pulse.value, _busy ? null : g.current));
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBot());
  }

  /// Computer players wait while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_busy) _maybeBot();
    } else {
      _botTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _botTimer?.cancel();
    _move.dispose();
    _pulse.dispose();
    _tokens.dispose();
    super.dispose();
  }

  Duration get _hop => Duration(milliseconds: store.fastMoves ? 140 : 240);

  /// Runs one animation segment; false if the screen went away meanwhile.
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
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted && id == _toastId) setState(() => _toast = null);
    });
  }

  void _maybeBot() {
    _botTimer?.cancel();
    if (g.isOver || !g.currentPlayer.isBot) return;
    _botTimer = Timer(
      Duration(milliseconds: store.fastMoves ? 450 : 800),
      () {
        if (mounted && !_busy) _roll();
      },
    );
  }

  Future<void> _roll() async {
    if (_busy || g.isOver) return;
    final p = g.current;
    setState(() {
      _busy = true;
      _actor = p;
    });
    final value = g.rollDie();
    sfx.play(Sound.dice);
    sfx.buzz();
    await _dice[p].currentState?.roll(value);
    if (!mounted) return;
    _lastRoll[p] = value;
    final r = g.play(value);
    if (value == 6 && !r.threeSixes && !r.blocked) sfx.play(Sound.six);
    if (!await _playOut(r)) return;
    if (r.won) return _finish(r);
    unawaited(store.save(g));
    setState(() {
      _busy = false;
      _actor = null;
    });
    _maybeBot();
  }

  /// Animates one turn: hops, then any ladder or snake.
  Future<bool> _playOut(TurnResult r) async {
    final p = r.player;
    final name = g.players[p].name;
    if (r.threeSixes) {
      _say('Three sixes! Turn over');
      return _pause(900);
    }
    if (r.blocked) {
      _say(r.from == 0 && g.rules.sixToStart
          ? 'Roll a 6 to start'
          : 'Need exactly ${BoardLayout.lastCell - r.from}');
      return _pause(r.extraTurn ? 500 : 800);
    }
    if (r.from == 0) _tokens.setWaiting(p, false);

    var at = unitCenter(r.from);
    for (final cell in r.steps) {
      final a = at, b = unitCenter(cell);
      final ok = await _animate(_hop, (t) {
        _tokens.move(p, Offset.lerp(a, b, t)!, lift: sin(pi * t) * 0.35);
      });
      if (!ok) return false;
      sfx.play(Sound.step);
      at = b;
    }

    final jf = r.jumpFrom;
    if (jf != null) {
      if (!await _pause(120)) return false;
      if (r.hitLadder) {
        _say('Ladder! $jf → ${r.end}');
        sfx.play(Sound.ladder);
        sfx.buzz();
        final a = unitCenter(jf), b = unitCenter(r.end);
        final rows = (a - b).distance;
        final ok = await _animate(
          Duration(milliseconds: (350 + rows * 110).round()),
          (t) {
            final e = Curves.easeInOut.transform(t);
            _tokens.move(p, Offset.lerp(a, b, e)!, lift: 0.12 * sin(pi * t));
          },
        );
        if (!ok) return false;
      } else {
        _say('Snake bite! $jf → ${r.end}');
        sfx.play(Sound.snake);
        sfx.buzz(strong: true);
        final path = snakePath(jf, r.end);
        final ok = await _animate(
          Duration(milliseconds: (500 + path.length * 12).round()),
          (t) {
            final e = Curves.easeIn.transform(t);
            _tokens.move(p, pointOnPath(path, e), lift: t < 1 ? 0.01 : 0);
          },
        );
        if (!ok) return false;
      }
    }
    _tokens.move(p, unitCenter(r.end));

    if (r.extraTurn) {
      _say(g.players[p].isBot ? '$name rolled a 6!' : 'Six! Roll again');
      if (!await _pause(350)) return false;
    }
    return true;
  }

  Future<void> _finish(TurnResult r) async {
    _botTimer?.cancel();
    setState(() {
      _celebrate = true;
      _actor = null;
    });
    sfx.play(Sound.win);
    sfx.buzz(strong: true);
    await store.recordGame(g);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    final again = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WinDialog(engine: g, theme: store.theme),
    );
    // A finished game is the natural break for a full-screen ad.
    await AdService.instance.maybeShowInterstitial();
    if (!mounted) return;
    if (again == true) {
      final board = g.board.id.startsWith('random_')
          ? BoardLayout.random(DateTime.now().millisecondsSinceEpoch)
          : g.board;
      final next = GameEngine(board: board, players: g.players, rules: g.rules);
      await store.save(next);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          gameRoute<void>(GameScreen(engine: next, store: store, sfx: sfx)));
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the game?'),
        content: const Text(
            'Your game is saved. You can continue it from the home screen.'),
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
    _botTimer?.cancel();
    await store.save(g);
    if (mounted) Navigator.of(context).pop();
  }

  int? _playerAt(_Corner c) {
    final seats = _seats[g.players.length]!;
    final i = seats.indexOf(c);
    return i < 0 ? null : i;
  }

  @override
  Widget build(BuildContext context) {
    final theme = store.theme;
    return PopScope(
      canPop: g.isOver,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: GameBackground(
          theme: theme,
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    _topBar(theme),
                    Expanded(
                      // Panels hug the board like Ludo; the board takes
                      // whatever height is left so small phones never
                      // overflow.
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _turnBanner(),
                            _panelRow(_Corner.topLeft, _Corner.topRight, theme),
                            Flexible(
                              child: LayoutBuilder(
                                builder: (context, box) => _board(theme,
                                    min(box.maxWidth - 16, box.maxHeight)),
                              ),
                            ),
                            _panelRow(
                                _Corner.bottomLeft, _Corner.bottomRight, theme),
                          ],
                        ),
                      ),
                    ),
                    const BannerAdSlot(),
                  ],
                ),
              ),
              if (_celebrate)
                Positioned.fill(
                  child: Confetti(colors: [
                    ...tokenColors,
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

  /// Whose turn it is, in their colour, between the top bar and the board.
  Widget _turnBanner() {
    if (g.isOver) return const SizedBox(height: 44);
    final p = g.players[_shown];
    final color = tokenColors[p.color];
    final humans = g.players.where((x) => !x.isBot).length;
    final String text;
    if (p.isBot) {
      text = '${p.name} is playing…';
    } else if (_busy) {
      text = humans == 1 ? 'Moving…' : '${p.name} is moving…';
    } else {
      text = humans == 1
          ? 'Your turn · tap the dice'
          : "${p.name}'s turn · tap the dice";
    }
    final dark = p.color == 2; // yellow needs dark text
    return SizedBox(
      height: 44,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, -0.3), end: Offset.zero)
                  .animate(a),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey(text),
            constraints:
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 32),
            padding: const EdgeInsets.fromLTRB(6, 3, 16, 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 12),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PawnIcon(color: p.color, size: 26),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dark ? Colors.black87 : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BoardTheme theme) {
    final fg = Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: fg),
            tooltip: 'Leave game',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              g.board.name,
              style: TextStyle(
                  color: fg, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
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

  Widget _panelRow(_Corner left, _Corner right, BoardTheme theme) {
    final l = _playerAt(left), r = _playerAt(right);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: l == null ? null : _panel(l, theme, mirrored: false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: r == null ? null : _panel(r, theme, mirrored: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(int i, BoardTheme theme, {required bool mirrored}) {
    final p = g.players[i];
    final color = tokenColors[p.color];
    final active = i == _shown && !g.isOver;
    final canTap = active && !_busy && !p.isBot;
    final pos = g.positions[i];
    final info = Expanded(
      child: Column(
        crossAxisAlignment:
            mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.isBot && !mirrored) ...[
                Icon(Icons.smart_toy_rounded, size: 14, color: theme.onPanel),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: theme.onPanel,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                ),
              ),
              if (p.isBot && mirrored) ...[
                const SizedBox(width: 3),
                Icon(Icons.smart_toy_rounded, size: 14, color: theme.onPanel),
              ],
            ],
          ),
          Text(
            g.winner == i
                ? 'Winner!'
                : pos == 0
                    ? 'Not started'
                    : 'On $pos',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: theme.onPanel.withValues(alpha: 0.75), fontSize: 12),
          ),
          if (canTap)
            Text('Tap to roll',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
    final dice = DiceView(
      key: _dice[i],
      value: _lastRoll[i],
      color: color,
      size: 50,
      enabled: canTap,
      dim: !active,
      onTap: _roll,
    );
    final children = [
      PawnIcon(color: p.color, size: 34),
      const SizedBox(width: 6),
      info,
      const SizedBox(width: 6),
      dice,
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: theme.panel.withValues(alpha: active ? 1 : 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: active ? 3 : 1.5),
        boxShadow: [
          if (active)
            BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 14,
                spreadRadius: 1),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: mirrored ? children.reversed.toList() : children,
      ),
    );
  }

  Widget _board(BoardTheme theme, double side) {
    return SizedBox.square(
      dimension: side,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(side / 28),
                boxShadow: [
                  const BoxShadow(
                      color: Colors.black45,
                      blurRadius: 18,
                      offset: Offset(0, 8)),
                  BoxShadow(
                      color: theme.accent.withValues(alpha: 0.35),
                      blurRadius: 24,
                      spreadRadius: 1),
                ],
              ),
              child: RepaintBoundary(
                child: CustomPaint(painter: BoardPainter(g.board, theme)),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: TokensPainter(_tokens)),
          ),
          Align(
            alignment: const Alignment(0, -0.1),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, a) => ScaleTransition(
                scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: _toast == null
                  ? const SizedBox.shrink()
                  : Container(
                      key: ValueKey(_toastId),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: theme.accent, width: 2),
                      ),
                      child: Text(
                        _toast!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WinDialog extends StatelessWidget {
  const _WinDialog({required this.engine, required this.theme});

  final GameEngine engine;
  final BoardTheme theme;

  @override
  Widget build(BuildContext context) {
    final g = engine;
    final w = g.winner!;
    final winner = g.players[w];
    final vsBot = g.players.any((p) => p.isBot);
    final title = vsBot
        ? (winner.isBot ? '${winner.name} wins' : 'You win!')
        : '${winner.name} wins!';
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
              vsBot && winner.isBot
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
            const SizedBox(height: 4),
            Text(
              'in ${g.rolls[w]} rolls · ${g.laddersClimbed[w]} ladders · '
              '${g.snakeBites[w]} snake bites',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            for (var k = 0; k < order.length; k++)
              ListTile(
                dense: true,
                leading: PawnIcon(color: g.players[order[k]].color, size: 30),
                title: Text(g.players[order[k]].name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(order[k] == w
                    ? 'Reached 100'
                    : g.positions[order[k]] == 0
                        ? 'Not started'
                        : 'Reached ${g.positions[order[k]]}'),
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
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Play again'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
