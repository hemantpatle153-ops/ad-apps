import 'package:flutter/material.dart';

import '../engine.dart';
import '../match.dart';
import '../sfx.dart';
import '../store.dart';
import '../themes.dart';
import 'game_screen.dart';
import 'kit.dart';
import 'pieces.dart';

const _botNames = ['Arjun', 'Meera', 'Kabir'];

/// Colours for a table of [count], starting with [first] and going
/// clockwise. Two players sit opposite each other.
List<int> seatColors(int first, int count) => switch (count) {
      2 => [first, (first + 2) % 4],
      _ => [for (var i = 0; i < count; i++) (first + i) % 4],
    };

/// Picks players, colour and rules for a game on this phone.
class LudoSetupScreen extends StatefulWidget {
  const LudoSetupScreen({
    super.key,
    required this.store,
    required this.sfx,
    required this.vsComputer,
  });

  final LudoStore store;
  final LudoSfx sfx;
  final bool vsComputer;

  @override
  State<LudoSetupScreen> createState() => _LudoSetupScreenState();
}

class _LudoSetupScreenState extends State<LudoSetupScreen> {
  LudoStore get store => widget.store;

  late int _count = widget.vsComputer ? 4 : 2;
  late int _color = store.favouriteColor;
  late GameRules _rules = store.rules;
  late final _names = [
    TextEditingController(text: store.playerName),
    for (var i = 2; i <= 4; i++) TextEditingController(text: 'Player $i'),
  ];

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _start() {
    widget.sfx.play(LudoSound.tap);
    final colors = seatColors(_color, _count);
    String name(int i) {
      final t = _names[i].text.trim();
      return t.isEmpty ? (i == 0 ? 'You' : 'Player ${i + 1}') : t;
    }

    final players = [
      for (var i = 0; i < _count; i++)
        widget.vsComputer && i > 0
            ? Player(
                name: _botNames[i - 1], color: colors[i], kind: PlayerKind.bot)
            : Player(name: name(i), color: colors[i], kind: PlayerKind.human),
    ];
    final first = _names[0].text.trim();
    if (first.isNotEmpty) store.playerName = first;
    store.favouriteColor = _color;
    store.rules = _rules;
    final engine = LudoEngine(players: players, rules: _rules);
    final id = LudoStore.newGameId();
    store.save(id, engine);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LudoGameScreen(
        engine: engine,
        store: store,
        sfx: widget.sfx,
        link: LocalLink(),
        gameId: id,
        me: 0,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = store.theme;
    final vs = widget.vsComputer;
    final colors = seatColors(_color, _count);
    return LudoPage(
      theme: theme,
      title: vs ? 'Play vs Computer' : 'Pass & Play',
      children: [
        LudoHeading(vs ? 'Players at the table' : 'How many players?'),
        LudoPanel(
          theme: theme,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              for (final n in [2, 3, 4])
                Expanded(
                  child: _Choice(
                    selected: _count == n,
                    color: theme.accent,
                    onTap: () => setState(() => _count = n),
                    child: Text('$n',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
        ),
        LudoHeading(vs ? 'Your colour' : 'Player 1 colour'),
        LudoPanel(
          theme: theme,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              for (var c = 0; c < 4; c++)
                Expanded(
                  child: _Choice(
                    selected: _color == c,
                    color: theme.colors[c],
                    onTap: () => setState(() => _color = c),
                    child: PieceIcon(color: theme.colors[c], size: 38),
                  ),
                ),
            ],
          ),
        ),
        const LudoHeading('Players'),
        LudoPanel(
          theme: theme,
          child: Column(
            children: [
              for (var i = 0; i < _count; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == _count - 1 ? 0 : 10),
                  child: Row(
                    children: [
                      PieceIcon(color: theme.colors[colors[i]], size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: vs && i > 0
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Text(_botNames[i - 1],
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  const Icon(Icons.smart_toy_rounded),
                                ],
                              )
                            : TextField(
                                controller: _names[i],
                                maxLength: 14,
                                style: TextStyle(color: theme.onPanel),
                                decoration: InputDecoration(
                                  labelText: i == 0
                                      ? 'Your name'
                                      : '${colorNames[colors[i]]} player',
                                  counterText: '',
                                  border: const OutlineInputBorder(),
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
        const LudoHeading('Rules'),
        LudoPanel(
          theme: theme,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Quick game'),
                subtitle: const Text('2 pieces each instead of 4'),
                value: _rules.tokens == 2,
                onChanged: (v) =>
                    setState(() => _rules = _rules.copyWith(tokens: v ? 2 : 4)),
              ),
              SwitchListTile(
                title: const Text('Only a 6 opens a piece'),
                subtitle: const Text('Off: a 1 or a 6 brings a piece out'),
                value: _rules.sixToRelease,
                onChanged: (v) =>
                    setState(() => _rules = _rules.copyWith(sixToRelease: v)),
              ),
              SwitchListTile(
                title: const Text('Three sixes lose the turn'),
                value: _rules.threeSixes,
                onChanged: (v) =>
                    setState(() => _rules = _rules.copyWith(threeSixes: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ChunkyButton(
          label: 'Start game',
          icon: Icons.play_arrow_rounded,
          onPressed: _start,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.color,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(4),
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? color : Colors.transparent, width: 3),
          ),
          child: child,
        ),
      );
}
