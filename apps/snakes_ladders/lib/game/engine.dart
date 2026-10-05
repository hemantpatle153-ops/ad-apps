import 'dart:math';

import 'board.dart';

enum PlayerKind { human, bot }

class Player {
  const Player({required this.name, required this.color, required this.kind});

  final String name;

  /// Index into the token colours (0 red, 1 green, 2 yellow, 3 blue).
  final int color;
  final PlayerKind kind;

  bool get isBot => kind == PlayerKind.bot;

  Map<String, dynamic> toJson() =>
      {'name': name, 'color': color, 'kind': kind.name};

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        name: j['name'] as String,
        color: j['color'] as int,
        kind: PlayerKind.values.byName(j['kind'] as String),
      );
}

class GameRules {
  const GameRules({
    this.exactFinish = true,
    this.sixExtraTurn = true,
    this.sixToStart = false,
  });

  /// You must roll exactly the number needed to reach 100.
  final bool exactFinish;

  /// A six gives another roll (three sixes in a row end the turn).
  final bool sixExtraTurn;

  /// A token stays off the board until its player rolls a six.
  final bool sixToStart;

  Map<String, dynamic> toJson() => {
        'exactFinish': exactFinish,
        'sixExtraTurn': sixExtraTurn,
        'sixToStart': sixToStart,
      };

  factory GameRules.fromJson(Map<String, dynamic> j) => GameRules(
        exactFinish: j['exactFinish'] as bool? ?? true,
        sixExtraTurn: j['sixExtraTurn'] as bool? ?? true,
        sixToStart: j['sixToStart'] as bool? ?? false,
      );
}

/// What happened on one roll, in the order the screen should animate it.
class TurnResult {
  const TurnResult({
    required this.player,
    required this.roll,
    required this.from,
    required this.steps,
    required this.end,
    this.jumpFrom,
    this.extraTurn = false,
    this.won = false,
    this.blocked = false,
    this.threeSixes = false,
  });

  final int player;
  final int roll;
  final int from;

  /// Every cell the token walks through, one per pip.
  final List<int> steps;

  /// Where the token finally rests after any snake or ladder.
  final int end;

  /// The cell holding the snake head or ladder foot, if one was hit.
  final int? jumpFrom;

  final bool extraTurn;
  final bool won;

  /// The roll couldn't be used (overshot 100, or waiting for a six).
  final bool blocked;

  /// Third six in a row: the turn ends without moving.
  final bool threeSixes;

  bool get hitLadder => jumpFrom != null && end > jumpFrom!;
  bool get hitSnake => jumpFrom != null && end < jumpFrom!;
}

/// The rules of Snakes and Ladders, with no UI. Fully serialisable so a game
/// can be saved and resumed.
class GameEngine {
  GameEngine({
    required this.board,
    required this.players,
    this.rules = const GameRules(),
    List<int>? positions,
    this.current = 0,
    this.sixStreak = 0,
    this.winner,
    this.turns = 0,
    List<int>? rolls,
    List<int>? snakeBites,
    List<int>? laddersClimbed,
    Random? random,
  })  : positions = positions ?? List.filled(players.length, 0),
        rolls = rolls ?? List.filled(players.length, 0),
        snakeBites = snakeBites ?? List.filled(players.length, 0),
        laddersClimbed = laddersClimbed ?? List.filled(players.length, 0),
        _random = random ?? Random();

  final BoardLayout board;
  final List<Player> players;
  final GameRules rules;

  /// 0 means not on the board yet; 1..100 is a cell.
  final List<int> positions;
  int current;
  int sixStreak;
  int? winner;
  int turns;

  final List<int> rolls;
  final List<int> snakeBites;
  final List<int> laddersClimbed;

  final Random _random;

  bool get isOver => winner != null;
  Player get currentPlayer => players[current];

  int rollDie() => 1 + _random.nextInt(6);

  /// Applies [roll] for the current player and advances the turn.
  TurnResult play(int roll) {
    assert(!isOver, 'Game already finished');
    assert(roll >= 1 && roll <= 6);
    final p = current;
    final from = positions[p];
    rolls[p]++;
    turns++;

    final six = roll == 6;
    sixStreak = six ? sixStreak + 1 : 0;

    if (rules.sixExtraTurn && sixStreak == 3) {
      _nextPlayer();
      return TurnResult(
        player: p,
        roll: roll,
        from: from,
        steps: const [],
        end: from,
        blocked: true,
        threeSixes: true,
      );
    }

    final extra = rules.sixExtraTurn && six;

    if (from == 0 && rules.sixToStart && !six) {
      _nextPlayer();
      return TurnResult(
        player: p,
        roll: roll,
        from: from,
        steps: const [],
        end: from,
        blocked: true,
      );
    }

    var target = from + roll;
    if (target > BoardLayout.lastCell) {
      if (rules.exactFinish) {
        // A six still earns its bonus roll even when it can't be used.
        if (!extra) _nextPlayer();
        return TurnResult(
          player: p,
          roll: roll,
          from: from,
          steps: const [],
          end: from,
          blocked: true,
          extraTurn: extra,
        );
      }
      target = BoardLayout.lastCell;
    }

    final steps = [for (var c = from + 1; c <= target; c++) c];
    final end = board.jumpFrom(target);
    positions[p] = end;
    int? jumpFrom;
    if (end != target) {
      jumpFrom = target;
      if (end > target) {
        laddersClimbed[p]++;
      } else {
        snakeBites[p]++;
      }
    }

    final won = end == BoardLayout.lastCell;
    if (won) {
      winner = p;
    } else if (!extra) {
      _nextPlayer();
    }
    return TurnResult(
      player: p,
      roll: roll,
      from: from,
      steps: steps,
      end: end,
      jumpFrom: jumpFrom,
      extraTurn: extra && !won,
      won: won,
    );
  }

  void _nextPlayer() {
    sixStreak = 0;
    current = (current + 1) % players.length;
  }

  /// Players ordered by how close they are to 100, winner first.
  List<int> get standings {
    final order = List.generate(players.length, (i) => i);
    order.sort((a, b) {
      if (a == winner) return -1;
      if (b == winner) return 1;
      return positions[b].compareTo(positions[a]);
    });
    return order;
  }

  Map<String, dynamic> toJson() => {
        'board': board.toJson(),
        'players': [for (final p in players) p.toJson()],
        'rules': rules.toJson(),
        'positions': positions,
        'current': current,
        'sixStreak': sixStreak,
        'winner': winner,
        'turns': turns,
        'rolls': rolls,
        'snakeBites': snakeBites,
        'laddersClimbed': laddersClimbed,
      };

  factory GameEngine.fromJson(Map<String, dynamic> j) {
    List<int> ints(String k) => [for (final v in j[k] as List) v as int];
    return GameEngine(
      board: BoardLayout.fromJson(j['board'] as Map<String, dynamic>),
      players: [
        for (final p in j['players'] as List)
          Player.fromJson(p as Map<String, dynamic>),
      ],
      rules: GameRules.fromJson(j['rules'] as Map<String, dynamic>),
      positions: ints('positions'),
      current: j['current'] as int,
      sixStreak: j['sixStreak'] as int,
      winner: j['winner'] as int?,
      turns: j['turns'] as int,
      rolls: ints('rolls'),
      snakeBites: ints('snakeBites'),
      laddersClimbed: ints('laddersClimbed'),
    );
  }
}
