import 'package:daily_sudoku/game_screen.dart';
import 'package:daily_sudoku/game_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sudoku_helpers.dart';

/// Cells left empty in the test puzzle: r0c0=5, r0c1=3, r0c2=4, r8c8=9.
const holes = [0, 1, 2, 80];

GameState testGame({String id = 'daily_2026-10-06', int hintsUsed = 0}) {
  final givens = List.of(knownSolution);
  for (final h in holes) {
    givens[h] = 0;
  }
  return GameState(
      id: id,
      title: 'Test',
      givens: givens,
      solution: List.of(knownSolution),
      hintsUsed: hintsUsed);
}

void main() {
  late Store store;
  late GameState game;
  final navKey = GlobalKey<NavigatorState>();

  Future<void> open(WidgetTester tester, GameState g) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    store = await Store.open();
    game = g;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey, home: const Scaffold(body: Text('host'))));
    navKey.currentState!.push(MaterialPageRoute(
        builder: (_) => GameScreen(game: g, store: store)));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  Finder cell(int i) => find
      .descendant(
          of: find.byType(GridView).first, matching: find.byType(GestureDetector))
      .at(i);

  Future<void> tapCell(WidgetTester tester, int i) async {
    await tester.tap(cell(i));
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, int v) async {
    await tester.tap(find.widgetWithText(FilledButton, '$v'));
    await tester.pump();
  }

  Future<void> tool(WidgetTester tester, String label) async {
    await tester.tap(find.textContaining(label));
    await tester.pump();
  }

  testWidgets('shows title, timer and mistake counter; saves on open', (t) async {
    await open(t, testGame());
    expect(find.text('Test'), findsOneWidget);
    expect(find.textContaining('00:00'), findsOneWidget);
    expect(find.textContaining('Mistakes 0/3'), findsOneWidget);
    expect(find.text('Hint (3)'), findsOneWidget);
    expect(store.loadCurrent()!.id, game.id);
    await t.pump(const Duration(seconds: 3));
    expect(game.seconds, 3);
    expect(find.textContaining('00:03'), findsOneWidget);
    await close(t);
  });

  testWidgets('a wrong digit counts a mistake and is saved', (t) async {
    await open(t, testGame());
    await tapCell(t, 0);
    await press(t, 9);
    expect(game.values[0], 9);
    expect(game.mistakes, 1);
    expect(find.textContaining('Mistakes 1/3'), findsOneWidget);
    expect(store.loadCurrent()!.values[0], 9);
    await close(t);
  });

  testWidgets('number pad shows only digits still to place', (t) async {
    await open(t, testGame());
    for (var v = 1; v <= 9; v++) {
      expect(find.widgetWithText(FilledButton, '$v'),
          [3, 4, 5, 9].contains(v) ? findsOneWidget : findsNothing,
          reason: 'digit $v');
    }
    await tool(t, 'Notes');
    expect(find.byType(FilledButton), findsNWidgets(9));
    await tool(t, 'Notes on');
    await tapCell(t, 80);
    await press(t, 9);
    expect(find.widgetWithText(FilledButton, '9'), findsNothing);
    await close(t);
  });

  testWidgets('given cells ignore input and erase', (t) async {
    await open(t, testGame());
    await tapCell(t, 3);
    await press(t, 5);
    await tool(t, 'Erase');
    expect(game.values[3], knownSolution[3]);
    expect(game.mistakes, 0);
    await close(t);
  });

  testWidgets('notes toggle on and off and clear when a peer is solved', (t) async {
    await open(t, testGame());
    await tool(t, 'Notes');
    expect(find.text('Notes on'), findsOneWidget);
    await tapCell(t, 1);
    await press(t, 3);
    await press(t, 5);
    expect(game.notes[1], {3, 5});
    await press(t, 3);
    expect(game.notes[1], {5});
    await tool(t, 'Notes on');
    await tapCell(t, 0);
    await press(t, 5); // correct: removes 5 from peer notes
    expect(game.values[0], 5);
    expect(game.notes[1], isEmpty);
    await close(t);
  });

  testWidgets('undo restores the previous value and notes', (t) async {
    await open(t, testGame());
    await tool(t, 'Notes');
    await tapCell(t, 2);
    await press(t, 7);
    await tool(t, 'Notes on');
    await press(t, 9);
    expect(game.values[2], 9);
    expect(game.notes[2], isEmpty);
    await tool(t, 'Undo');
    expect(game.values[2], 0);
    expect(game.notes[2], {7});
    await tool(t, 'Undo');
    expect(game.notes[2], isEmpty);
    await close(t);
  });

  testWidgets('erase clears a wrong digit but not a correct one', (t) async {
    await open(t, testGame());
    await tapCell(t, 1);
    await press(t, 9);
    await tool(t, 'Erase');
    expect(game.values[1], 0);
    await press(t, 3);
    await tool(t, 'Erase');
    expect(game.values[1], 3);
    await close(t);
  });

  testWidgets('hint fills the selected cell and counts down', (t) async {
    await open(t, testGame());
    await tapCell(t, 2);
    await tool(t, 'Hint');
    expect(game.values[2], 4);
    expect(game.hintsUsed, 1);
    expect(find.text('Hint (2)'), findsOneWidget);
    // With a solved cell selected, the hint picks the first unsolved cell.
    await tool(t, 'Hint');
    expect(game.values[0], 5);
    await close(t);
  });

  testWidgets('without free hints or an ad, a snackbar explains', (t) async {
    await open(t, testGame(hintsUsed: 3));
    await tool(t, 'Hint (0)');
    await t.pump();
    expect(find.text('No more hints right now. Try again shortly.'), findsOneWidget);
    expect(game.values[0], 0);
    await close(t);
  });

  testWidgets('third mistake offers a free second chance', (t) async {
    await open(t, testGame());
    await tapCell(t, 0);
    for (final v in [3, 4, 9]) {
      await press(t, v);
    }
    await t.pumpAndSettle();
    expect(find.text('Game over'), findsOneWidget);
    await t.tap(find.text('Second chance'));
    await t.pumpAndSettle();
    expect(game.mistakes, 2);
    expect(game.completed, isFalse);
    await close(t);
  });

  testWidgets('quitting after game over clears the saved game', (t) async {
    await open(t, testGame());
    await tapCell(t, 80);
    for (final v in [3, 4, 5]) {
      await press(t, v);
    }
    await t.pumpAndSettle();
    await t.tap(find.text('Quit'));
    await t.pumpAndSettle();
    expect(game.completed, isTrue);
    expect(store.loadCurrent(), isNull);
    expect(find.text('host'), findsOneWidget);
    await close(t);
  });

  testWidgets('solving the daily records the win and the streak', (t) async {
    await open(t, testGame());
    for (final i in holes) {
      await tapCell(t, i);
      await press(t, knownSolution[i]);
    }
    await t.pumpAndSettle();
    expect(find.text('Solved!'), findsOneWidget);
    expect(game.completed, isTrue);
    expect(store.solved, 1);
    expect(store.dailyDone, {'2026-10-06'});
    expect(store.loadCurrent(), isNull);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('host'), findsOneWidget);
    await close(t);
  });

  testWidgets('solving a regular game records best time per level', (t) async {
    await open(t, testGame(id: 'hard'));
    await t.pump(const Duration(seconds: 5));
    for (final i in holes) {
      await tapCell(t, i);
      await press(t, knownSolution[i]);
    }
    await t.pumpAndSettle();
    expect(store.bestSeconds('hard'), 5);
    expect(store.dailyDone, isEmpty);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    await close(t);
  });
}
