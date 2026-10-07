// Helpers for Play Store screenshots made with `flutter test`.
//
// Each app has screenshots/store_test.dart that pumps its real screens and
// calls [shot]. Run from the app folder:
//   flutter test screenshots/store_test.dart --update-goldens
// PNGs land in apps/<app>/store/screenshots/ (1080 x 2160, phone portrait).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone portrait, 2:1 as Play allows: 411 x 822 dp at 2.625x.
const phoneSize = Size(1080, 2160);
const phoneRatio = 2.625;

/// Loads Roboto and Material Icons from the Flutter SDK so text and icons
/// render for real instead of the test font's boxes.
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  ByteData read(File f) => ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer);
  final roboto = FontLoader('Roboto');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      roboto.addFont(Future.value(read(f)));
    }
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(read(File('${dir.path}/MaterialIcons-Regular.otf'))));
  await icons.load();
}

/// Sets the phone size for one test.
void usePhone(WidgetTester tester) {
  tester.view.physicalSize = phoneSize;
  tester.view.devicePixelRatio = phoneRatio;
  addTearDown(tester.view.reset);
}

/// Saves the whole screen as store/screenshots/<name>.png.
Future<void> shot(WidgetTester tester, String name) async {
  // Real shadows for the picture only; the test binding wants them off again
  // before the test ends.
  debugDisableShadows = false;
  try {
    // Repaint every layer, or cached layers keep the debug shadow outlines.
    void visit(RenderObject o) {
      o.markNeedsPaint();
      o.visitChildren(visit);
    }
    visit(tester.binding.renderView);
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp).first,
      matchesGoldenFile('../store/screenshots/$name.png'),
    );
  } finally {
    debugDisableShadows = true;
  }
}

/// Lets real async work (isolates, file IO) finish between frames.
Future<void> settleReal(WidgetTester tester, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
