import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../game/board.dart';
import '../game/engine.dart';
import '../game/store.dart';
import '../game/themes.dart';
import 'board_painter.dart';
import 'game_screen.dart';
import 'tokens.dart';

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
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameScreen(engine: engine, store: store, sfx: widget.sfx),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = store.theme;
    final t = Theme.of(context).textTheme;
    final vs = widget.vsComputer;
    return Scaffold(
      appBar: AppBar(title: Text(vs ? 'Play vs Computer' : 'Pass & Play')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(vs ? 'Opponents' : 'Players', style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final n in [2, 3, 4])
                ButtonSegment(
                  value: n,
                  label: Text(
                      vs ? '${n - 1} bot${n > 2 ? 's' : ''}' : '$n players'),
                ),
            ],
            selected: {_count},
            onSelectionChanged: (s) => setState(() => _count = s.first),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  PawnIcon(color: i, size: 40),
                  const SizedBox(width: 8),
                  Expanded(
                    child: vs && i > 0
                        ? ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_botNames[i - 1]),
                            subtitle: Text('Computer · ${tokenColorNames[i]}'),
                            trailing: const Icon(Icons.smart_toy_rounded),
                          )
                        : TextField(
                            controller: _names[i],
                            maxLength: 14,
                            decoration: InputDecoration(
                              labelText: i == 0
                                  ? 'Your name (${tokenColorNames[i]})'
                                  : '${tokenColorNames[i]} player',
                              counterText: '',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text('Board', style: t.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 156,
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
                    width: 118,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox.square(
                          dimension: 100,
                          child: CustomPaint(
                            painter: BoardPainter(b, theme, showNumbers: false),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(b.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${b.ladders.length} ladders · ${b.snakes.length} snakes',
                            style: t.bodySmall,
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
            padding: const EdgeInsets.only(top: 4),
            child: Text(_layout.description, style: t.bodySmall),
          ),
          const SizedBox(height: 16),
          Text('Rules', style: t.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exact roll to finish'),
            subtitle: const Text('Overshooting 100 means no move'),
            value: _rules.exactFinish,
            onChanged: (v) => setState(() => _rules = GameRules(
                exactFinish: v,
                sixExtraTurn: _rules.sixExtraTurn,
                sixToStart: _rules.sixToStart)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Six gives another roll'),
            subtitle: const Text('Three sixes in a row ends the turn'),
            value: _rules.sixExtraTurn,
            onChanged: (v) => setState(() => _rules = GameRules(
                exactFinish: _rules.exactFinish,
                sixExtraTurn: v,
                sixToStart: _rules.sixToStart)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Roll a 6 to start'),
            subtitle: const Text('Tokens wait off the board until a six'),
            value: _rules.sixToStart,
            onChanged: (v) => setState(() => _rules = GameRules(
                exactFinish: _rules.exactFinish,
                sixExtraTurn: _rules.sixExtraTurn,
                sixToStart: v)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Start game', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}
