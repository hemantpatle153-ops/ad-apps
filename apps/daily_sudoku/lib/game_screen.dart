import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'game_state.dart';
import 'main.dart' show formatTime;

const maxMistakes = 3;
const freeHints = 3;

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game, required this.store});
  final GameState game;
  final Store store;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  int? _selected;
  bool _notes = false;
  Timer? _timer;
  final List<(int, int, Set<int>)> _undo = [];

  GameState get g => widget.game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    widget.store.saveCurrent(g);
  }

  void _startTimer() {
    _timer?.cancel();
    if (g.completed) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => g.seconds++);
      if (g.seconds % 10 == 0) widget.store.saveCurrent(g);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    } else {
      _timer?.cancel();
      if (!g.completed) widget.store.saveCurrent(g);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (!g.completed) widget.store.saveCurrent(g);
    super.dispose();
  }

  bool _isGiven(int i) => g.givens[i] != 0;

  void _input(int v) {
    final i = _selected;
    if (i == null || _isGiven(i) || g.completed) return;
    if (g.values[i] == g.solution[i]) return;
    _undo.add((i, g.values[i], Set.of(g.notes[i])));
    setState(() {
      if (_notes) {
        g.values[i] = 0;
        if (!g.notes[i].remove(v)) g.notes[i].add(v);
        return;
      }
      g.values[i] = v;
      g.notes[i].clear();
      if (v != g.solution[i]) {
        g.mistakes++;
      } else {
        _clearPeerNotes(i, v);
      }
    });
    widget.store.saveCurrent(g);
    if (g.mistakes >= maxMistakes) {
      _gameOver();
    } else if (g.isSolved) {
      _win();
    }
  }

  void _clearPeerNotes(int i, int v) {
    final r = i ~/ 9, c = i % 9;
    for (var k = 0; k < 81; k++) {
      final kr = k ~/ 9, kc = k % 9;
      if (kr == r || kc == c || (kr ~/ 3 == r ~/ 3 && kc ~/ 3 == c ~/ 3)) {
        g.notes[k].remove(v);
      }
    }
  }

  void _erase() {
    final i = _selected;
    if (i == null || _isGiven(i) || g.values[i] == g.solution[i]) return;
    _undo.add((i, g.values[i], Set.of(g.notes[i])));
    setState(() {
      g.values[i] = 0;
      g.notes[i].clear();
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    final (i, v, n) = _undo.removeLast();
    setState(() {
      g.values[i] = v;
      g.notes[i]
        ..clear()
        ..addAll(n);
    });
  }

  Future<void> _hint() async {
    if (g.completed) return;
    if (g.hintsUsed < freeHints) {
      g.hintsUsed++;
      _revealOne();
      return;
    }
    if (!AdService.instance.rewardedReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No more hints right now. Try again shortly.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Out of free hints'),
        content: const Text('Watch a short video to get one more hint?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('No thanks')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Watch')),
        ],
      ),
    );
    if (ok != true) return;
    _timer?.cancel();
    final earned = await AdService.instance.showRewarded();
    if (!mounted) return;
    _startTimer();
    if (earned) _revealOne();
  }

  void _revealOne() {
    var i = _selected;
    if (i == null || g.values[i] == g.solution[i]) {
      i = List.generate(81, (k) => k)
          .firstWhere((k) => g.values[k] != g.solution[k], orElse: () => -1);
    }
    if (i < 0) return;
    final cell = i;
    setState(() {
      g.values[cell] = g.solution[cell];
      g.notes[cell].clear();
      _clearPeerNotes(cell, g.solution[cell]);
      _selected = cell;
    });
    widget.store.saveCurrent(g);
    if (g.isSolved) _win();
  }

  Future<void> _win() async {
    _timer?.cancel();
    g.completed = true;
    final daily = g.id.startsWith('daily_');
    await widget.store.recordWin(daily ? 'daily' : g.id, g.seconds);
    if (daily) await widget.store.markDailyDone(g.id.substring(6));
    await widget.store.clearCurrent();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Solved!'),
        content: Text('Time ${formatTime(g.seconds)}, '
            'mistakes ${g.mistakes}, hints ${g.hintsUsed}.'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('Done')),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
    // Natural break: the puzzle is finished.
    AdService.instance.maybeShowInterstitial();
  }

  Future<void> _gameOver() async {
    _timer?.cancel();
    final keepGoing = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Game over'),
        content: const Text('That was your third mistake.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            // AdMob asks that users agree to a rewarded ad before it plays.
            child: Text(AdService.instance.rewardedReady
                ? 'Watch an ad for a second chance'
                : 'Second chance'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Quit'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (keepGoing == true) {
      // A second chance is a reward, so it needs a finished rewarded ad when
      // one is available; without one it is free.
      var allowed = true;
      if (AdService.instance.rewardedReady) {
        allowed = await AdService.instance.showRewarded();
      }
      if (!mounted) return;
      if (allowed) {
        setState(() => g.mistakes = maxMistakes - 1);
        _startTimer();
        return;
      }
    }
    g.completed = true;
    await widget.store.clearCurrent();
    if (!mounted) return;
    Navigator.pop(context);
    AdService.instance.maybeShowInterstitial();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sel = _selected;
    final selValue = sel == null ? 0 : g.values[sel];
    return Scaffold(
      bottomNavigationBar: const BannerAdSlot(),
      appBar: AppBar(
        title: Text(g.title),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('${formatTime(g.seconds)}   '
                  'Mistakes ${g.mistakes}/$maxMistakes'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _grid(cs, sel, selValue),
                  ),
                ),
              ),
            ),
            _tools(cs),
            _numberPad(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _grid(ColorScheme cs, int? sel, int selValue) {
    return DecoratedBox(
      decoration:
          BoxDecoration(border: Border.all(color: cs.onSurface, width: 2)),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 9),
        itemCount: 81,
        itemBuilder: (_, i) {
          final r = i ~/ 9, c = i % 9;
          final v = g.values[i];
          final related = sel != null &&
              (sel ~/ 9 == r ||
                  sel % 9 == c ||
                  (sel ~/ 27 == r ~/ 3 && (sel % 9) ~/ 3 == c ~/ 3));
          final same = v != 0 && v == selValue;
          final wrong = v != 0 && v != g.solution[i];
          Color? bg;
          if (i == sel) {
            bg = cs.primaryContainer;
          } else if (same) {
            bg = cs.secondaryContainer;
          } else if (related) {
            bg = cs.surfaceContainerHighest;
          }
          final thinLine = cs.onSurface.withValues(alpha: .25);
          return GestureDetector(
            onTap: () => setState(() => _selected = i),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  right: c == 8
                      ? BorderSide.none
                      : c % 3 == 2
                          ? BorderSide(color: cs.onSurface, width: 2)
                          : BorderSide(color: thinLine, width: .5),
                  bottom: r == 8
                      ? BorderSide.none
                      : r % 3 == 2
                          ? BorderSide(color: cs.onSurface, width: 2)
                          : BorderSide(color: thinLine, width: .5),
                ),
              ),
              child: v != 0
                  ? Center(
                      child: FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            '$v',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: _isGiven(i)
                                  ? FontWeight.bold
                                  : FontWeight.w400,
                              color: wrong
                                  ? cs.error
                                  : _isGiven(i)
                                      ? cs.onSurface
                                      : cs.primary,
                            ),
                          ),
                        ),
                      ),
                    )
                  : _notesView(g.notes[i], cs),
            ),
          );
        },
      ),
    );
  }

  Widget _notesView(Set<int> n, ColorScheme cs) {
    if (n.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      crossAxisCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var k = 1; k <= 9; k++)
          Center(
            child: FittedBox(
              child: Text(n.contains(k) ? '$k' : '',
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            ),
          ),
      ],
    );
  }

  Widget _tools(ColorScheme cs) {
    Widget tool(IconData icon, String label, VoidCallback onTap,
            {bool active = false}) =>
        TextButton(
          onPressed: onTap,
          child: Column(
            children: [
              Icon(icon, color: active ? cs.primary : null),
              Text(label),
            ],
          ),
        );
    final hintsLeft = (freeHints - g.hintsUsed).clamp(0, freeHints);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        tool(Icons.undo, 'Undo', _undoLast),
        tool(Icons.backspace_outlined, 'Erase', _erase),
        tool(Icons.edit_note, _notes ? 'Notes on' : 'Notes',
            () => setState(() => _notes = !_notes),
            active: _notes),
        tool(Icons.lightbulb_outline, 'Hint ($hintsLeft)', _hint),
      ],
    );
  }

  Widget _numberPad() {
    int remaining(int v) {
      var placed = 0;
      for (var k = 0; k < 81; k++) {
        if (g.values[k] == v && g.solution[k] == v) placed++;
      }
      return 9 - placed;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          for (var v = 1; v <= 9; v++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: remaining(v) <= 0 && !_notes
                    ? const SizedBox(height: 56)
                    : FilledButton.tonal(
                        style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 56)),
                        onPressed: () => _input(v),
                        child:
                            Text('$v', style: const TextStyle(fontSize: 22)),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
