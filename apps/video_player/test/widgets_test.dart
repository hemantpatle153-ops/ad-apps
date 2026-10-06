import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/player/player_overlays.dart';
import 'package:video_player_app/src/player/player_screen.dart'
    show FitMode, Rotation;
import 'package:video_player_app/src/settings.dart';
import 'package:video_player_app/src/widgets/pin_pad.dart';
import 'package:video_player_app/src/widgets/video_thumb.dart';
import 'package:video_player_app/src/widgets/video_tile.dart';

import 'support/fixtures.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: SingleChildScrollView(child: child))),
    );

Future<void> tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
    await tester.pump();
  }
}

int filledDots(WidgetTester tester, Color primary) => tester
    .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
    .where((c) => (c.decoration as BoxDecoration?)?.color == primary)
    .length;

void main() {
  group('enums', () {
    test('FitMode labels and ratios', () {
      expect(FitMode.values.map((m) => m.label),
          ['Fit', 'Stretch', 'Crop', '16:9', '4:3']);
      expect(FitMode.wide.ratio, closeTo(16 / 9, 1e-9));
      expect(FitMode.classic.ratio, closeTo(4 / 3, 1e-9));
      expect(FitMode.fit.ratio, isNull);
      expect(FitMode.crop.boxFit, BoxFit.cover);
      expect(FitMode.stretch.boxFit, BoxFit.fill);
    });
    test('Rotation labels', () {
      expect(Rotation.values.map((r) => r.label),
          ['Landscape', 'Portrait', 'Auto-rotate']);
    });
  });

  group('PinPad', () {
    for (final pin in ['1234', '0000', '9870', '5555']) {
      testWidgets('entering $pin calls onComplete and clears', (tester) async {
        final got = <String>[];
        await tester.pumpWidget(host(PinPad(
            title: 'Enter PIN',
            subtitle: 'for the private folder',
            onComplete: (p) {
              got.add(p);
              return true;
            })));
        expect(find.text('Enter PIN'), findsOneWidget);
        expect(find.text('for the private folder'), findsOneWidget);
        await tapDigits(tester, pin);
        final primary =
            Theme.of(tester.element(find.byType(PinPad))).colorScheme.primary;
        expect(filledDots(tester, primary), 4);
        await tester.pump(const Duration(milliseconds: 150));
        expect(got, [pin]);
        await tester.pumpAndSettle();
        expect(filledDots(tester, primary), 0);
      });
    }

    testWidgets('backspace removes the last digit', (tester) async {
      final got = <String>[];
      await tester.pumpWidget(host(PinPad(
          title: 'T',
          onComplete: (p) {
            got.add(p);
            return true;
          })));
      await tapDigits(tester, '12');
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      await tapDigits(tester, '345');
      await tester.pump(const Duration(milliseconds: 150));
      expect(got, ['1345']);
      await tester.pumpAndSettle();
    });

    testWidgets('wrong PIN shakes and lets the user retry', (tester) async {
      final got = <String>[];
      await tester.pumpWidget(host(PinPad(
          title: 'T',
          onComplete: (p) {
            got.add(p);
            return p == '2222';
          })));
      await tapDigits(tester, '1111');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      await tapDigits(tester, '2222');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(got, ['1111', '2222']);
    });

    testWidgets('custom length 6 ignores extra presses', (tester) async {
      final got = <String>[];
      await tester.pumpWidget(host(PinPad(
          title: 'T',
          length: 6,
          onComplete: (p) {
            got.add(p);
            return true;
          })));
      expect(find.byType(AnimatedContainer), findsNWidgets(6));
      await tapDigits(tester, '1234567');
      await tester.pump(const Duration(milliseconds: 150));
      expect(got, ['123456']);
      await tester.pumpAndSettle();
    });
  });

  group('overlays', () {
    testWidgets('GestureIndicator shows text, subtext and level',
        (tester) async {
      await tester.pumpWidget(host(const GestureIndicator(
          icon: Icons.volume_up, text: '75%', subtext: 'Volume', level: 1.4)));
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, 1.0, reason: 'level is clamped');
    });

    testWidgets('GestureIndicator without level has no bar', (tester) async {
      await tester.pumpWidget(
          host(const GestureIndicator(icon: Icons.zoom_in, text: '1.5x')));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    for (final forward in [true, false]) {
      testWidgets('DoubleTapRipple forward=$forward', (tester) async {
        await tester.pumpWidget(MaterialApp(
            home: SizedBox(
                width: 800,
                height: 400,
                child: DoubleTapRipple(forward: forward, seconds: 10))));
        expect(find.text(forward ? '+10 s' : '-10 s'), findsOneWidget);
        expect(
            find.byIcon(forward
                ? Icons.fast_forward_rounded
                : Icons.fast_rewind_rounded),
            findsOneWidget);
      });
    }

    testWidgets('SubtitleText joins non-empty lines', (tester) async {
      await tester.pumpWidget(host(const SubtitleText(
          lines: ['Hello', '  ', 'world'],
          size: 20,
          color: Colors.yellow,
          background: true)));
      final t = tester.widget<Text>(find.byType(Text));
      expect(t.data, 'Hello\nworld');
      expect(t.style!.fontSize, 20);
      expect(t.style!.color, Colors.yellow);
      expect(t.style!.shadows, isNull);
    });

    testWidgets('SubtitleText hides when blank and outlines without background',
        (tester) async {
      await tester.pumpWidget(host(const SubtitleText(
          lines: ['', ' '], size: 20, color: Colors.white, background: false)));
      expect(find.byType(Text), findsNothing);
      await tester.pumpWidget(host(const SubtitleText(
          lines: ['Hi'], size: 30, color: Colors.white, background: false)));
      expect(
          tester.widget<Text>(find.byType(Text)).style!.shadows, hasLength(3));
    });
  });

  group('video list widgets', () {
    testWidgets('VideoThumb placeholder with badge and progress',
        (tester) async {
      await tester.pumpWidget(
          host(const VideoThumb(assetId: null, badge: '1:15', progress: 0.4)));
      expect(find.byIcon(Icons.movie_rounded), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0.4);
    });

    testWidgets('VideoThumb without progress has no bar', (tester) async {
      await tester.pumpWidget(host(const VideoThumb(assetId: null, badge: '')));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('VideoTile shows title, meta, NEW badge and resume bar',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.open();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final v = makeVideo('5',
          title: 'Beach.mp4',
          seconds: 600,
          size: 740 * 1024,
          created: now,
          folder: 'Trip');
      var taps = 0, more = 0;
      await tester.pumpWidget(host(VideoTile(
          video: v,
          settings: s,
          onTap: () => taps++,
          onMore: () => more++,
          showFolder: true)));
      await tester.pump();
      expect(find.text('Beach.mp4'), findsOneWidget);
      expect(find.text('Trip  ·  740 KB  ·  1080p'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      await tester.tap(find.text('Beach.mp4'));
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      expect(taps, 1);
      expect(more, 1);

      s.savePosition(
          '5', const Duration(minutes: 3), const Duration(minutes: 10));
      await tester
          .pumpWidget(host(VideoTile(video: v, settings: s, onTap: () {})));
      await tester.pump();
      expect(find.text('NEW'), findsNothing, reason: 'already played');
      expect(find.text('740 KB  ·  1080p'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          closeTo(0.3, 1e-9));
    });

    testWidgets('old unplayed video is not NEW', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.open();
      final v = makeVideo('6', title: 'Old.mp4', created: 1000);
      await tester
          .pumpWidget(host(VideoTile(video: v, settings: s, onTap: () {})));
      await tester.pump();
      expect(find.text('NEW'), findsNothing);
    });
  });
}
