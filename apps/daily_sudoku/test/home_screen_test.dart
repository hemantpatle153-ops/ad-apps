import 'package:daily_sudoku/game_screen.dart';
import 'package:daily_sudoku/game_state.dart';
import 'package:daily_sudoku/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> openFrom(WidgetTester tester, String label) async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store)));
    await tester.tap(find.text(label));
    await tester.pump();
    // Generation runs on a real isolate, so let real time pass for it.
    for (var i = 0; i < 100 && find.byType(GameScreen).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Dispose the game screen so its clock timer stops.
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('a new game opens instead of spinning forever', (tester) async {
    await openFrom(tester, 'Easy');
  });

  testWidgets("today's puzzle opens instead of spinning forever", (tester) async {
    await openFrom(tester, "Today's puzzle");
  });
}
