import 'dart:math';

import 'package:snakes_ladders/game/board.dart';
import 'package:snakes_ladders/game/engine.dart' as sl;
import 'package:snakes_ladders/ludo/engine.dart' as ludo;

/// All eight combinations of the Snakes & Ladders rule switches.
final slRuleCombos = [
  for (final e in [true, false])
    for (final s in [true, false])
      for (final t in [true, false])
        sl.GameRules(exactFinish: e, sixExtraTurn: s, sixToStart: t),
];

String slRulesName(sl.GameRules r) =>
    'exact=${r.exactFinish} six+=${r.sixExtraTurn} sixStart=${r.sixToStart}';

sl.GameEngine slGame({
  BoardLayout board = BoardLayout.classic,
  int players = 2,
  sl.GameRules rules = const sl.GameRules(),
  int seed = 0,
  bool bots = false,
}) =>
    sl.GameEngine(
      board: board,
      players: [
        for (var i = 0; i < players; i++)
          sl.Player(
              name: 'P$i',
              color: i,
              kind: bots && i > 0 ? sl.PlayerKind.bot : sl.PlayerKind.human),
      ],
      rules: rules,
      random: Random(seed),
    );

/// Colours clockwise for a Ludo table of [n] players, as the setup screen
/// seats them.
List<int> ludoColors(int n) => switch (n) {
      2 => const [3, 1],
      3 => const [3, 0, 1],
      _ => const [3, 0, 1, 2],
    };

ludo.LudoEngine ludoGame({
  int players = 2,
  ludo.GameRules rules = const ludo.GameRules(),
  ludo.PlayerKind kind = ludo.PlayerKind.human,
  int seed = 0,
}) {
  final colors = ludoColors(players);
  return ludo.LudoEngine(
    players: [
      for (var i = 0; i < players; i++)
        ludo.Player(name: 'L$i', color: colors[i], kind: kind),
    ],
    rules: rules,
    random: Random(seed),
  );
}
