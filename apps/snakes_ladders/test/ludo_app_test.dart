import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snakes_ladders/audio/sfx.dart';
import 'package:snakes_ladders/game/store.dart';
import 'package:snakes_ladders/ludo/sfx.dart';
import 'package:snakes_ladders/ludo/store.dart';
import 'package:snakes_ladders/ludo/ui/setup_screen.dart';
import 'package:snakes_ladders/main.dart';

/// Pumps frames for [ms] milliseconds; screens animate forever, so
/// pumpAndSettle would never return.
Future<void> settle(WidgetTester tester, [int ms = 1000]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets('pick Ludo and start vs computer on ${size.width.toInt()} px',
        (tester) async {
      SharedPreferences.setMockInitialValues({'sound': false});
      final store = await Store.open();
      final ludo = await LudoStore.open();
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(PartyApp(
          store: store, sfx: Sfx(store), ludo: ludo, ludoSfx: LudoSfx(ludo)));
      await settle(tester);
      expect(find.text('Snakes & Ladders'), findsOneWidget);

      await tester.tap(find.text('Ludo'));
      await settle(tester);
      await tester.tap(find.text('vs Computer'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Start game'),
        300,
        scrollable: find
            .descendant(
                of: find.byType(LudoSetupScreen),
                matching: find.byType(Scrollable))
            .first,
      );
      await settle(tester);
      await tester.tap(find.text('Start game'));
      await settle(tester);

      expect(find.text('Your turn · tap the dice'), findsOneWidget);
      expect(ludo.savedGames.length, 1);

      await tester.tap(find.byTooltip('Leave game'));
      await settle(tester);
      await tester.tap(find.text('Leave'));
      await settle(tester);
      expect(ludo.savedGames.length, 1);
      await tester.scrollUntilVisible(
          find.textContaining('Unfinished games'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Unfinished games'), findsOneWidget);
    });
  }
}
