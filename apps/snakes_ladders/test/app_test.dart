import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snakes_ladders/audio/sfx.dart';
import 'package:snakes_ladders/game/store.dart';
import 'package:snakes_ladders/main.dart';
import 'package:snakes_ladders/ui/setup_screen.dart';

/// Pumps frames for [ms] milliseconds; screens animate forever, so
/// pumpAndSettle would never return.
Future<void> settle(WidgetTester tester, [int ms = 1000]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // A small phone and a typical one; any layout overflow fails the test.
  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets('start a game vs computer on a ${size.width.toInt()} px screen',
        (tester) async {
      SharedPreferences.setMockInitialValues({'sound': false});
      final store = await Store.open();
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(SnakesApp(store: store, sfx: Sfx(store)));
      await settle(tester);

      await tester.tap(find.text('Play vs Computer'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Start game'),
        300,
        scrollable: find
            .descendant(
                of: find.byType(SetupScreen), matching: find.byType(Scrollable))
            .first,
      );
      await settle(tester);
      await tester.tap(find.text('Start game'));
      await settle(tester);

      expect(find.text('Your turn · tap the dice'), findsOneWidget);
      expect(store.savedGames.length, 1);

      // Leave through the confirm dialog; the game stays saved.
      await tester.tap(find.byTooltip('Leave game'));
      await settle(tester);
      await tester.tap(find.text('Leave'));
      await settle(tester);
      expect(store.savedGames.length, 1);
      await tester.scrollUntilVisible(
          find.textContaining('Unfinished games'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Unfinished games'), findsOneWidget);
    });
  }
}
