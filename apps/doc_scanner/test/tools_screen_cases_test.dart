import 'package:doc_scanner/screens/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const notOnePdf = {
    Tool.idCard,
    Tool.businessCard,
    Tool.photos,
    Tool.compare,
    Tool.jpgToPdf,
    Tool.wordToPdf,
  };

  group('tool menu rules', () {
    for (final t in Tool.values) {
      test('${t.name} onePdf is ${!notOnePdf.contains(t)}', () {
        expect(t.onePdf, !notOnePdf.contains(t));
        expect(t.title, isNotEmpty);
        expect(t.subtitle, isNotEmpty);
      });
    }
    test('subtitles are unique', () {
      expect(Tool.values.map((t) => t.subtitle).toSet().length, Tool.values.length);
    });
    for (final g in ToolGroup.values) {
      test('group ${g.name} has tools', () {
        expect(Tool.values.where((t) => t.group == g), isNotEmpty);
      });
    }
  });

  group('tools grid', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ToolsScreen())));
    }

    testWidgets('shows every group heading in order', (tester) async {
      await pump(tester);
      const headings = ['Scan & compare', 'Organize', 'Optimize', 'Convert', 'Edit & sign', 'Security'];
      final ys = [for (final h in headings) tester.getTopLeft(find.text(h)).dy];
      expect(ys, [...ys]..sort());
    });

    testWidgets('every tile shows its subtitle and icon', (tester) async {
      await pump(tester);
      for (final t in Tool.values) {
        expect(find.text(t.subtitle), findsOneWidget, reason: t.name);
        expect(find.byIcon(t.icon), findsWidgets, reason: t.name);
      }
      expect(find.byType(Card), findsNWidgets(Tool.values.length));
    });

    testWidgets('tiles sit under their group heading', (tester) async {
      await pump(tester);
      final merge = tester.getTopLeft(find.text(Tool.merge.title)).dy;
      final protect = tester.getTopLeft(find.text(Tool.protect.title)).dy;
      expect(merge, greaterThan(tester.getTopLeft(find.text('Organize')).dy));
      expect(merge, lessThan(tester.getTopLeft(find.text('Optimize')).dy));
      expect(protect, greaterThan(tester.getTopLeft(find.text('Security')).dy));
    });
  });
}
