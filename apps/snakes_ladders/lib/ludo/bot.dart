import 'dart:math';

import 'engine.dart';

/// Picks a move for a computer player (or for a friend who dropped out of
/// an online game). Prefers captures, getting home and staying safe.
int chooseMove(LudoEngine g, List<int> movable, {Random? random}) {
  final rnd = random ?? Random();
  final p = g.current;
  final roll = g.lastRoll;
  final color = g.players[p].color;
  var best = movable.first;
  var bestScore = double.negativeInfinity;
  for (final t in movable) {
    final from = g.tokens[p][t];
    final to = from == Track.yard ? 0 : from + roll;
    var s = rnd.nextDouble(); // breaks ties so bots don't look scripted
    final sq = Track.square(color, to);
    if (to == Track.home) s += 80;
    if (from == Track.yard) s += 55;
    if (sq != null && !Track.isSafe(sq) && _opponentsOn(g, p, sq) > 0) {
      s += 100;
    }
    if (from <= Track.lastTrack && to > Track.lastTrack) s += 35;
    if (sq != null && Track.isSafe(sq)) s += 18;
    final fromSq = Track.square(color, from);
    if (fromSq != null && !Track.isSafe(fromSq) && _threat(g, p, fromSq) > 0) {
      s += 30;
    }
    if (sq != null && !Track.isSafe(sq)) s -= 45 * _threat(g, p, sq);
    s += to * 0.15;
    if (s > bestScore) {
      bestScore = s;
      best = t;
    }
  }
  return best;
}

int _opponentsOn(LudoEngine g, int p, int sq) {
  var n = 0;
  for (var o = 0; o < g.players.length; o++) {
    if (o == p) continue;
    for (final t in g.tokens[o]) {
      if (Track.square(g.players[o].color, t) == sq) n++;
    }
  }
  return n;
}

/// Opponent tokens within six squares behind [sq] that could land on it.
int _threat(LudoEngine g, int p, int sq) {
  var n = 0;
  for (var o = 0; o < g.players.length; o++) {
    if (o == p) continue;
    final c = g.players[o].color;
    for (final t in g.tokens[o]) {
      final s = Track.square(c, t);
      if (s == null) continue;
      final gap = (sq - s + Track.loop) % Track.loop;
      // The opponent must still be on the loop when it gets there.
      if (gap >= 1 && gap <= 6 && t + gap <= Track.lastTrack) n++;
    }
  }
  return n;
}
