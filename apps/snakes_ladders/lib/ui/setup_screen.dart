import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../game/board.dart';
import '../game/engine.dart';
import '../game/store.dart';
import '../game/themes.dart';
import 'board_painter.dart';
import 'game_screen.dart';
import 'tokens.dart';
import 'widgets.dart';

const _botNames = ['Arjun', 'Meera', 'Kabir'];

/// Picks players, board and rules before a game.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.store,
    required this.sfx,
    required this.vsComputer,
  });

  final Store store;
  final Sfx sfx;
  final bool vsComputer;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  Store get store => widget.store;

  int _count = 2;
  int _board = 0; // index into presets, or presets.length for Surprise
  late GameRules _rules = store.rules;
  late final _names = [
    TextEditingController(text: store.playerName),
    for (var i = 2; i <= 4; i++) TextEditingController(text: 'Player $i'),
  ];
  final _random = BoardLayout.random(DateTime.now().millisecondsSinceEpoch);

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  BoardLayout get _layout => _board < BoardLayout.presets.length
      ? BoardLayout.presets[_board]
      : _random;

  void _start() {
    widget.sfx.play(Sound.tap);
    String name(int i, String fallback) {
      final t = _names[i].text.trim();
      return t.isEmpty ? fallback : t;
    }

    final players = <Player>[
      for (var i = 0; i < _count; i++)
        widget.vsComputer && i > 0
            ? Player(name: _botNames[i - 1], color: i, kind: PlayerKind.bot)
            : Player(
                name: name(i, i == 0 ? 'You' : 'Player ${i + 1}'),
                color: i,
                kind: PlayerKind.human),
    ];
    final first = _names[0].text.trim();
    if (first.isNotEmpty) store.playerName = first;
    store.rules = _rules;
    final engine = GameEngine(board: _layout, players: players, rules: _rules);
    store.save(engine);
    Navigator.of(context).pushReplacement(gameRoute<void>(
        GameScreen(engine: engine, store: store, sfx: widget.sfx)));
  }

  Widget _rule(String title, String sub, bool value, ValueChanged<bool> on) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub),
        value: value,
        onChanged: on,
      );

  @override
  Widget build(BuildContext context) {
    final theme = store.theme;
    final vs = widget.vsComputer;
    final full = store.savedGames.length >= Store.maxSaved;
    final fg = theme.onPanel;
    return Scaffold(
      body: GameBackground(
        theme: theme,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              Row(
                children: [
                  const BackButton(color: Colors.white),
                  Text(
                    vs ? 'Play vs Computer' : 'Pass & Play',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              SectionTitle(vs ? 'Opponents' : 'Players'),
              Panel(
                theme: theme,
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (final n in [2, 3, 4])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: _Chip(
                                label: vs
                                    ? '${n - 1} bot${n > 2 ? 's' : ''}'
                                    : '$n players',
                                selected: _count == n,
                                color: theme.accent,
                                textColor: fg,
                                onTap: () => setState(() => _count = n),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _count; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            PawnIcon(color: i, size: 42),
                            const SizedBox(width: 8),
                            Expanded(
                              child: vs && i > 0
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(_botNames[i - 1],
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                              Text(
                                                  'Computer · ${tokenColorNames[i]}',
                                                  style: TextStyle(
                                                      color: fg.withValues(
                                                          alpha: 0.7))),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.smart_toy_rounded),
                                      ],
                                    )
                                  : TextField(
                                      controller: _names[i],
                                      maxLength: 14,
                                      style: TextStyle(color: fg),
                                      decoration: InputDecoration(
                                        labelText: i == 0
                                            ? 'Your name (${tokenColorNames[i]})'
                                            : '${tokenColorNames[i]} player',
                                        labelStyle: TextStyle(
                                            color: fg.withValues(alpha: 0.7)),
                                        counterText: '',
                                        filled: true,
                                        fillColor: tokenColors[i]
                                            .withValues(alpha: 0.12),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: BorderSide.none,
                                        ),
                                        isDense: true,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SectionTitle('Board'),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: BoardLayout.presets.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final b = i < BoardLayout.presets.length
                        ? BoardLayout.presets[i]
                        : _random;
                    final selected = i == _board;
                    return GestureDetector(
                      onTap: () => setState(() => _board = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 124,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.panel
                              .withValues(alpha: selected ? 1 : 0.75),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected ? theme.accent : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox.square(
                                dimension: 100,
                                child: CustomPaint(
                                  painter: BoardPainter(b, theme,
                                      showNumbers: false),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(b.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: fg, fontWeight: FontWeight.w800)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${b.ladders.length} ladders · ${b.snakes.length} snakes',
                                style: TextStyle(
                                    color: fg.withValues(alpha: 0.7),
                                    fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(_layout.description,
                    style: const TextStyle(color: Colors.white70)),
              ),
              const SectionTitle('Rules'),
              Panel(
                theme: theme,
                padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                child: Column(
                  children: [
                    _rule(
                        'Exact roll to finish',
                        'Overshooting 100 means no move',
                        _rules.exactFinish,
                        (v) => setState(() => _rules = GameRules(
                            exactFinish: v,
                            sixExtraTurn: _rules.sixExtraTurn,
                            sixToStart: _rules.sixToStart))),
                    _rule(
                        'Six gives another roll',
                        'Three sixes in a row ends the turn',
                        _rules.sixExtraTurn,
                        (v) => setState(() => _rules = GameRules(
                            exactFinish: _rules.exactFinish,
                            sixExtraTurn: v,
                            sixToStart: _rules.sixToStart))),
                    _rule(
                        'Roll a 6 to start',
                        'Tokens wait off the board until a six',
                        _rules.sixToStart,
                        (v) => setState(() => _rules = GameRules(
                            exactFinish: _rules.exactFinish,
                            sixExtraTurn: _rules.sixExtraTurn,
                            sixToStart: v))),
                  ],
                ),
              ),
              if (full)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                  child: Text(
                    'You have ${Store.maxSaved} unfinished games. Starting this '
                    'one replaces the oldest.',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              const SizedBox(height: 18),
              BigButton(
                color: tokenColors[vs ? 0 : 1],
                icon: Icons.play_arrow_rounded,
                label: 'Start game',
                sub: '${_layout.name} · $_count players',
                onTap: _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : textColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? Colors.black87 : textColor,
            ),
          ),
        ),
      );
}
