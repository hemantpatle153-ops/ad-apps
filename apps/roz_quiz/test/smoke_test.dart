import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('app opens on Today and plays the daily quiz', (tester) async {
    final h = Harness();
    await pumpApp(tester, h);
    expect(find.text('Daily Quiz · 7 Oct'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playDaily')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const ValueKey('option1')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Your result'), findsOneWidget);
  });
}
