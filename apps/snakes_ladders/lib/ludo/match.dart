import 'dart:async';

import 'engine.dart';

/// One thing a player did. A game is the list of these in order, so phones
/// that apply the same list end in the same state.
sealed class GameAction {
  const GameAction(this.player);

  final int player;

  Map<String, dynamic> toJson();

  static GameAction fromJson(Map<String, dynamic> j) {
    final p = j['p'] as int;
    return switch (j['t']) {
      'roll' => RollAction(p, j['v'] as int),
      'move' => MoveAction(p, j['k'] as int),
      _ => throw FormatException('Unknown action ${j['t']}'),
    };
  }

  /// Whether [g] can take this action now. Out-of-turn or stale actions
  /// from another phone are skipped instead of corrupting the game.
  bool validFor(LudoEngine g) {
    if (g.isOver || player != g.current) return false;
    return switch (this) {
      RollAction(:final value) =>
        g.phase == Phase.roll && value >= 1 && value <= 6,
      MoveAction(:final token) => g.phase == Phase.move &&
          g.movableFor(player, g.lastRoll).contains(token),
    };
  }
}

class RollAction extends GameAction {
  const RollAction(super.player, this.value);
  final int value;

  @override
  Map<String, dynamic> toJson() => {'t': 'roll', 'p': player, 'v': value};
}

class MoveAction extends GameAction {
  const MoveAction(super.player, this.token);
  final int token;

  @override
  Map<String, dynamic> toJson() => {'t': 'move', 'p': player, 'k': token};
}

/// Carries actions between the game screen and wherever the game lives:
/// this phone alone, or an online room.
abstract class MatchLink {
  /// Actions in order, each with its index in the game.
  Stream<(int, GameAction)> get actions;

  /// Sends the action that should become number [index]. Online, another
  /// phone may have taken that slot first; then this one is dropped.
  Future<void> send(int index, GameAction action);

  /// Whether this phone acts for [player] (people here and computer
  /// players in a local game; just your own seat online).
  bool controls(LudoEngine g, int player);

  bool get online;

  Future<void> close();
}

/// A game played on this phone only.
class LocalLink implements MatchLink {
  final _out = StreamController<(int, GameAction)>();

  @override
  Stream<(int, GameAction)> get actions => _out.stream;

  @override
  Future<void> send(int index, GameAction action) async =>
      _out.add((index, action));

  @override
  bool controls(LudoEngine g, int player) => true;

  @override
  bool get online => false;

  @override
  Future<void> close() => _out.close();
}
