import 'dart:math';

/// Who controls a seat. [remote] is a friend playing on their own phone.
enum PlayerKind { human, bot, remote }

class Player {
  const Player({required this.name, required this.color, required this.kind});

  final String name;

  /// Board colour: 0 red (top-left), 1 green (top-right), 2 yellow
  /// (bottom-right), 3 blue (bottom-left). Play goes clockwise.
  final int color;
  final PlayerKind kind;

  bool get isBot => kind == PlayerKind.bot;

  Player copyWith({String? name, PlayerKind? kind}) =>
      Player(name: name ?? this.name, color: color, kind: kind ?? this.kind);

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
    this.tokens = 4,
    this.sixToRelease = true,
    this.threeSixes = true,
  });

  /// Tokens per player: 4 for a full game, 2 for a quick one.
  final int tokens;

  /// Only a six brings a token out of the yard (otherwise a one or a six).
  final bool sixToRelease;

  /// A third six in a row cancels the turn.
  final bool threeSixes;

  GameRules copyWith({int? tokens, bool? sixToRelease, bool? threeSixes}) =>
      GameRules(
        tokens: tokens ?? this.tokens,
        sixToRelease: sixToRelease ?? this.sixToRelease,
        threeSixes: threeSixes ?? this.threeSixes,
      );

  Map<String, dynamic> toJson() => {
        'tokens': tokens,
        'sixToRelease': sixToRelease,
        'threeSixes': threeSixes,
      };

  factory GameRules.fromJson(Map<String, dynamic> j) => GameRules(
        tokens: j['tokens'] as int? ?? 4,
        sixToRelease: j['sixToRelease'] as bool? ?? true,
        threeSixes: j['threeSixes'] as bool? ?? true,
      );
}

/// A token's progress along its own route:
/// [yard] at home base, 0..50 on the shared track (0 is the colour's start
/// square), 51..55 up its home column, and [home] once finished.
abstract final class Track {
  static const yard = -1;
  static const lastTrack = 50;
  static const home = 56;

  /// Squares on the shared loop.
  static const loop = 52;

  /// Start squares and the four star squares: nobody is captured here.
  static const safeSquares = {0, 8, 13, 21, 26, 34, 39, 47};

  static int startOf(int color) => color * 13;

  /// Shared-loop square for a token, or null off the loop.
  static int? square(int color, int progress) =>
      progress < 0 || progress > lastTrack
          ? null
          : (startOf(color) + progress) % loop;

  static bool isSafe(int square) => safeSquares.contains(square);
}

enum Phase { roll, move }

/// What happened when a die was thrown.
class RollResult {
  const RollResult({
    required this.player,
    required this.value,
    required this.movable,
    this.threeSixes = false,
  });

  final int player;
  final int value;

  /// Tokens that can use this roll. Empty means the turn passes.
  final List<int> movable;

  /// Third six in a row: the turn ends without a move.
  final bool threeSixes;

  bool get passes => threeSixes || movable.isEmpty;
}

class Capture {
  const Capture(this.player, this.token, this.from);
  final int player;
  final int token;

  /// Progress the captured token had, so the screen can animate it home.
  final int from;
}

/// What a move did, in the order the screen should animate it.
class MoveResult {
  const MoveResult({
    required this.player,
    required this.token,
    required this.from,
    required this.to,
    required this.captures,
    required this.extraTurn,
    required this.finishedToken,
    required this.finishedPlayer,
    required this.gameOver,
  });

  final int player;
  final int token;
  final int from;
  final int to;
  final List<Capture> captures;
  final bool extraTurn;

  /// The token reached the centre.
  final bool finishedToken;

  /// That was the player's last token.
  final bool finishedPlayer;
  final bool gameOver;

  /// Every progress value the token passes through, one per pip.
  List<int> get steps =>
      from == Track.yard ? const [0] : [for (var p = from + 1; p <= to; p++) p];
}

/// The rules of Ludo, with no UI. Fully serialisable so a game can be saved,
/// resumed or replayed from a list of rolls and moves on another phone.
class LudoEngine {
  LudoEngine({
    required this.players,
    this.rules = const GameRules(),
    List<List<int>>? tokens,
    this.current = 0,
    this.phase = Phase.roll,
    this.lastRoll = 0,
    this.sixStreak = 0,
    List<int>? finishOrder,
    this.turns = 0,
    List<int>? captures,
    List<int>? sixes,
    Random? random,
  })  : tokens = tokens ??
            [
              for (var i = 0; i < players.length; i++)
                List.filled(rules.tokens, Track.yard),
            ],
        finishOrder = finishOrder ?? [],
        captures = captures ?? List.filled(players.length, 0),
        sixes = sixes ?? List.filled(players.length, 0),
        _random = random ?? Random();

  final List<Player> players;
  final GameRules rules;

  /// tokens[player][token] is that token's progress (see [Track]).
  final List<List<int>> tokens;
  int current;
  Phase phase;

  /// The value waiting to be used while [phase] is [Phase.move].
  int lastRoll;
  int sixStreak;

  /// Players in the order they got all their tokens home.
  final List<int> finishOrder;
  int turns;
  final List<int> captures;
  final List<int> sixes;

  final Random _random;

  Player get currentPlayer => players[current];

  bool hasFinished(int p) => tokens[p].every((t) => t == Track.home);

  /// The game ends when one player is left, or when every person at the
  /// table is done and only computer players remain.
  bool get isOver {
    final left = [
      for (var p = 0; p < players.length; p++)
        if (!hasFinished(p)) p
    ];
    if (left.length <= 1) return true;
    return left.every((p) => players[p].isBot);
  }

  int? get winner => finishOrder.isEmpty ? null : finishOrder.first;

  int rollDie() => 1 + _random.nextInt(6);

  /// Tokens that could move [roll] squares right now.
  List<int> movableFor(int player, int roll) => [
        for (var t = 0; t < tokens[player].length; t++)
          if (_target(tokens[player][t], roll) != null) t
      ];

  int? _target(int from, int roll) {
    if (from == Track.home) return null;
    if (from == Track.yard) {
      final out = roll == 6 || (!rules.sixToRelease && roll == 1);
      return out ? 0 : null;
    }
    final to = from + roll;
    return to > Track.home ? null : to;
  }

  /// Applies a throw for the current player.
  RollResult roll(int value) {
    assert(phase == Phase.roll && !isOver);
    assert(value >= 1 && value <= 6);
    final p = current;
    turns++;
    if (value == 6) {
      sixes[p]++;
      sixStreak++;
    } else {
      sixStreak = 0;
    }
    if (rules.threeSixes && sixStreak == 3) {
      _nextPlayer();
      return RollResult(
          player: p, value: value, movable: const [], threeSixes: true);
    }
    final movable = movableFor(p, value);
    if (movable.isEmpty) {
      // A six still earns its bonus throw when nothing can move.
      if (value != 6) _nextPlayer();
      return RollResult(player: p, value: value, movable: movable);
    }
    lastRoll = value;
    phase = Phase.move;
    return RollResult(player: p, value: value, movable: movable);
  }

  /// Moves [token] of the current player by the pending roll.
  MoveResult move(int token) {
    assert(phase == Phase.move);
    final p = current;
    final from = tokens[p][token];
    final to = _target(from, lastRoll);
    if (to == null) throw ArgumentError('Token $token cannot move $lastRoll');
    tokens[p][token] = to;

    final caught = <Capture>[];
    final sq = Track.square(players[p].color, to);
    if (sq != null && !Track.isSafe(sq)) {
      for (var o = 0; o < players.length; o++) {
        if (o == p) continue;
        for (var t = 0; t < tokens[o].length; t++) {
          if (Track.square(players[o].color, tokens[o][t]) == sq) {
            caught.add(Capture(o, t, tokens[o][t]));
            tokens[o][t] = Track.yard;
          }
        }
      }
    }
    captures[p] += caught.length;

    final finishedToken = to == Track.home;
    final finishedPlayer = finishedToken && hasFinished(p);
    if (finishedPlayer) finishOrder.add(p);
    final over = isOver;
    if (over) _rankTheRest();

    // A six, a capture or a token reaching home earns another throw.
    final extra = !over &&
        !finishedPlayer &&
        (lastRoll == 6 || caught.isNotEmpty || finishedToken);
    phase = Phase.roll;
    if (!over && !extra) _nextPlayer();
    return MoveResult(
      player: p,
      token: token,
      from: from,
      to: to,
      captures: caught,
      extraTurn: extra,
      finishedToken: finishedToken,
      finishedPlayer: finishedPlayer,
      gameOver: over,
    );
  }

  void _nextPlayer() {
    sixStreak = 0;
    phase = Phase.roll;
    if (isOver) return;
    do {
      current = (current + 1) % players.length;
    } while (hasFinished(current));
  }

  /// Total progress, used to rank players who didn't finish.
  int score(int p) =>
      tokens[p].fold(0, (s, t) => s + (t == Track.yard ? 0 : t + 1));

  void _rankTheRest() {
    final rest = [
      for (var p = 0; p < players.length; p++)
        if (!finishOrder.contains(p)) p
    ]..sort((a, b) => score(b).compareTo(score(a)));
    finishOrder.addAll(rest);
  }

  /// Players in finishing order, then by progress.
  List<int> get standings {
    final rest = [
      for (var p = 0; p < players.length; p++)
        if (!finishOrder.contains(p)) p
    ]..sort((a, b) => score(b).compareTo(score(a)));
    return [...finishOrder, ...rest];
  }

  /// Share of the whole route covered, 0 to 1, for the progress bars.
  double progress(int p) => score(p) / (tokens[p].length * (Track.home + 1));

  Map<String, dynamic> toJson() => {
        'players': [for (final p in players) p.toJson()],
        'rules': rules.toJson(),
        'tokens': tokens,
        'current': current,
        'phase': phase.name,
        'lastRoll': lastRoll,
        'sixStreak': sixStreak,
        'finishOrder': finishOrder,
        'turns': turns,
        'captures': captures,
        'sixes': sixes,
      };

  factory LudoEngine.fromJson(Map<String, dynamic> j) {
    List<int> ints(Object? v) => [for (final x in v as List) x as int];
    return LudoEngine(
      players: [
        for (final p in j['players'] as List)
          Player.fromJson(p as Map<String, dynamic>),
      ],
      rules: GameRules.fromJson(j['rules'] as Map<String, dynamic>),
      tokens: [for (final t in j['tokens'] as List) ints(t)],
      current: j['current'] as int,
      phase: Phase.values.byName(j['phase'] as String),
      lastRoll: j['lastRoll'] as int,
      sixStreak: j['sixStreak'] as int,
      finishOrder: ints(j['finishOrder']),
      turns: j['turns'] as int,
      captures: ints(j['captures']),
      sixes: ints(j['sixes']),
    );
  }
}
