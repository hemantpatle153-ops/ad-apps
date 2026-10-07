// Play Store screenshots. Run: flutter test screenshots/store_test.dart --update-goldens
import 'package:daily_sudoku/game_screen.dart';
import 'package:daily_sudoku/game_state.dart';
import 'package:daily_sudoku/main.dart';
import 'package:daily_sudoku/sudoku_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../tool/screenshots/shot.dart';

void main() {
  setUpAll(loadRealFonts);

  testWidgets('home', (tester) async {
    usePhone(tester);
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    await tester.pumpWidget(SudokuApp(store: store));
    await tester.pumpAndSettle();
    await shot(tester, '01_home');
  });

  testWidgets('game in progress', (tester) async {
    usePhone(tester);
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    final p = SudokuEngine(20261007).generate(Difficulty.medium);
    final g = GameState.fromPuzzle('shot', 'Medium', p);
    // Fill some cells so the board looks mid-game, plus a few notes.
    var filled = 0;
    for (var i = 0; i < 81 && filled < 14; i++) {
      if (g.givens[i] == 0 && i % 3 == 0) {
        g.values[i] = g.solution[i];
        filled++;
      }
    }
    for (var i = 0, n = 0; i < 81 && n < 4; i++) {
      if (g.values[i] == 0 && i % 5 == 1) {
        g.notes[i].addAll({g.solution[i], (g.solution[i] % 9) + 1});
        n++;
      }
    }
    g.seconds = 312;
    await tester.pumpWidget(SudokuApp(store: store));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => GameScreen(game: g, store: store)));
    await tester.pumpAndSettle();
    // Select an empty cell so the highlight shows.
    await shot(tester, '02_game');
    await tester.pumpWidget(const SizedBox());
  });
}
