import 'package:doc_scanner/screens/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every tool has a tile', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ToolsScreen())));
    for (final t in Tool.values) {
      expect(find.text(t.title), findsOneWidget, reason: t.title);
    }
  });

  test('tool titles are unique', () {
    final titles = Tool.values.map((t) => t.title).toSet();
    expect(titles.length, Tool.values.length);
  });

  test('document menu offers only one-PDF tools', () {
    expect(Tool.sign.onePdf, isTrue);
    expect(Tool.compare.onePdf, isFalse);
    expect(Tool.jpgToPdf.onePdf, isFalse);
  });
}
