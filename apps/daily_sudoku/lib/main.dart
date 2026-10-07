import 'dart:isolate';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'game_screen.dart';
import 'game_state.dart';
import 'sudoku_engine.dart';

const packageName = 'in.onlysoftware.daily_sudoku';

// Rahul's published Google Doc (same text as website/build.py's page).
const privacyPolicyUrl =
    'https://docs.google.com/document/d/e/2PACX-1vTaZv3owS5iiOH0PkLw7wnCHDw5u2rNyOyLbHogItpRQyKczECgA0o1FEJ3oDmwQxfkOijJHOj4tgtC/pub';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  runApp(SudokuApp(store: store));
  // Consent and ads start after the first frame so the app opens instantly.
  AdService.instance.init(AdConfig.fromEnvironment(rewarded: true));
}

class SudokuApp extends StatelessWidget {
  const SudokuApp({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F51B5);
    return MaterialApp(
      title: 'Daily Sudoku',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      home: HomeScreen(store: store),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final Store store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  Store get store => widget.store;

  Future<void> _open(GameState g) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen(game: g, store: store)),
    );
    if (mounted) setState(() {});
  }

  /// Shows the spinner while [make] runs on another isolate, then opens the
  /// puzzle. Always clears the spinner, even if generation fails.
  Future<void> _start(
      Future<Puzzle> Function() make, GameState Function(Puzzle) toGame) async {
    setState(() => _busy = true);
    Puzzle? p;
    try {
      p = await make();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't create a puzzle. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (p == null || !mounted) return;
    await _open(toGame(p));
  }

  Future<void> _newGame(Difficulty d) {
    final seed = DateTime.now().microsecondsSinceEpoch;
    return _start(() => generatePuzzle(seed, d),
        (p) => GameState.fromPuzzle(d.name, d.label, p));
  }

  Future<void> _daily() async {
    final today = DateTime.now();
    final key = Store.dayKey(today);
    final current = store.loadCurrent();
    if (current != null && current.id == 'daily_$key') return _open(current);
    return _start(() => generateDaily(today),
        (p) => GameState.fromPuzzle('daily_$key', 'Daily $key', p));
  }

  String _days(int n) => n == 1 ? '1 day' : '$n days';

  @override
  Widget build(BuildContext context) {
    final current = store.loadCurrent();
    final today = DateTime.now();
    final doneToday = store.dailyDone.contains(Store.dayKey(today));
    final streak = store.dailyStreak(today);
    final theme = Theme.of(context);
    return Scaffold(
      bottomNavigationBar: const BannerAdSlot(),
      appBar: AppBar(
        title: const Text('Daily Sudoku'),
        actions: const [AppMenu()],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const Icon(Icons.calendar_today, size: 36),
                    title: const Text("Today's puzzle"),
                    subtitle: Text(doneToday
                        ? 'Solved. Streak: ${_days(streak)}'
                        : 'Streak: ${_days(streak)}'),
                    trailing: Icon(
                        doneToday ? Icons.check_circle : Icons.play_arrow),
                    onTap: doneToday ? null : _daily,
                  ),
                ),
                if (current != null && !current.completed) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Continue'),
                      subtitle: Text(
                          '${current.title} - ${formatTime(current.seconds)}'),
                      onTap: () => _open(current),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text('New game', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final d in Difficulty.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.tonal(
                      onPressed: () => _newGame(d),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(d.label),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Puzzles solved: ${store.solved}',
                    textAlign: TextAlign.center),
                for (final d in Difficulty.values)
                  if (store.bestSeconds(d.name) > 0)
                    Text(
                        'Best ${d.label}: ${formatTime(store.bestSeconds(d.name))}',
                        textAlign: TextAlign.center),
              ],
            ),
    );
  }
}

// Isolate.run sends its closure to the new isolate. A closure written inside
// a State method can capture the State (and its BuildContext), which can't be
// sent, so Isolate.run throws. These top-level closures only hold plain values.
Future<Puzzle> generatePuzzle(int seed, Difficulty d) =>
    Isolate.run(() => SudokuEngine(seed).generate(d));

Future<Puzzle> generateDaily(DateTime day) =>
    Isolate.run(() => SudokuEngine.daily(day));

String formatTime(int s) =>
    '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

/// Rate, privacy policy and (in the EU/UK) ad privacy choices.
class AppMenu extends StatelessWidget {
  const AppMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AdService.instance.privacyOptionsRequired(),
      builder: (context, snap) => PopupMenuButton<VoidCallback>(
        onSelected: (fn) => fn(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () => openStorePage(packageName),
            child: const Text('Rate this app'),
          ),
          PopupMenuItem(
            value: () => openLink(privacyPolicyUrl),
            child: const Text('Privacy policy'),
          ),
          if (snap.data == true)
            PopupMenuItem(
              value: AdService.instance.showPrivacyOptions,
              child: const Text('Ad privacy choices'),
            ),
        ],
      ),
    );
  }
}
