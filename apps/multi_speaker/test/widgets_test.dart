import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/settings.dart';
import 'package:multi_speaker/src/speaker_delay.dart';
import 'package:multi_speaker/src/sync/speaker.dart';
import 'package:multi_speaker/src/sync/sync_controller.dart';
import 'package:multi_speaker/src/ui/bluetooth_help_screen.dart';
import 'package:multi_speaker/src/ui/common.dart';
import 'package:multi_speaker/src/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/gen.dart';

const _channel = MethodChannel('in.onlysoftware.multi_speaker/native');

void _mockNative(Future<Object?>? Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

SyncController _sync() => SyncController(
      engine: ScriptedEngine(),
      hostNowUs: () => 0,
      latencyUs: () => 0,
      trackPath: (_) => null,
      trackTitle: (_) => '',
    );

void main() {
  tearDown(() => _mockNative(null));

  group('SyncChip', () {
    final cases = <(SyncPhase, int?, double?), String>{
      (SyncPhase.idle, null, null): 'Waiting for music',
      (SyncPhase.waitingForSong, null, null): 'Getting the song',
      (SyncPhase.waitingForSong, null, 0.0): 'Getting the song 0%',
      (SyncPhase.waitingForSong, null, 0.426): 'Getting the song 43%',
      (SyncPhase.waitingForSong, null, 1.0): 'Getting the song 100%',
      (SyncPhase.paused, null, null): 'Paused',
      (SyncPhase.starting, null, null): 'Starting in sync',
      (SyncPhase.pausedHere, null, null): 'Paused on this phone',
      (SyncPhase.playing, null, null): 'Playing in sync',
      (SyncPhase.playing, 0, null): 'In sync (0 ms)',
      (SyncPhase.playing, 12, null): 'In sync (12 ms)',
      (SyncPhase.playing, -35, null): 'In sync (35 ms)',
      (SyncPhase.playing, 80, null): 'In sync (80 ms)',
    };
    cases.forEach((c, text) {
      testWidgets('${c.$1.name} err=${c.$2} progress=${c.$3} shows "$text"', (tester) async {
        final sync = _sync();
        sync.phase.value = c.$1;
        sync.errorMs.value = c.$2;
        await tester.pumpWidget(_app(SyncChip(sync: sync, downloadProgress: c.$3)));
        expect(find.text(text), findsOneWidget);
        await tester.runAsync(sync.dispose);
      });
    });
    testWidgets('updates when the phase changes', (tester) async {
      final sync = _sync();
      await tester.pumpWidget(_app(SyncChip(sync: sync)));
      expect(find.text('Waiting for music'), findsOneWidget);
      sync.phase.value = SyncPhase.playing;
      await tester.pump();
      expect(find.text('Playing in sync'), findsOneWidget);
      sync.errorMs.value = 7;
      await tester.pump();
      expect(find.text('In sync (7 ms)'), findsOneWidget);
      await tester.runAsync(sync.dispose);
    });
    testWidgets('a big error is shown in a warning colour', (tester) async {
      final sync = _sync()
        ..phase.value = SyncPhase.playing
        ..errorMs.value = 41;
      await tester.pumpWidget(_app(SyncChip(sync: sync)));
      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      final scheme = Theme.of(tester.element(find.byType(Chip))).colorScheme;
      expect(icon.color, scheme.tertiary);
      sync.errorMs.value = 40;
      await tester.pump();
      expect(tester.widget<Icon>(find.byIcon(Icons.check_circle)).color,
          Colors.green.shade600);
      await tester.runAsync(sync.dispose);
    });
  });

  // The speaker card's delay slider, wired to this phone's saved delay the
  // way the host and guest screens wire it.
  group('Speaker delay', () {
    Future<(Settings, SpeakerDelay)> setup(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final s = await Settings.load();
      return (s, SpeakerDelay(s));
    }

    Widget card(SpeakerDelay d) => ListenableBuilder(
          listenable: d,
          builder: (context, _) => SpeakerCard(
            name: 'Me',
            output: d.outputLabel,
            bluetooth: d.bluetooth,
            isThisPhone: true,
            level: const SpeakerLevel(),
            onLevel: (_) {},
            delayMs: d.delayMs,
            onDelay: (ms) => d.delayMs = ms,
          ),
        );

    Future<void> openDelay(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Sync delay'));
      await tester.pumpAndSettle();
    }

    Slider delaySlider(WidgetTester tester) =>
        tester.widget<Slider>(find.byType(Slider).last);

    for (final ms in [0, 120, 600]) {
      testWidgets('shows the phone delay of $ms ms', (tester) async {
        final (_, d) = await setup({'delay_phone': ms});
        await tester.pumpWidget(_app(card(d)));
        await openDelay(tester);
        expect(find.text('$ms ms'), findsOneWidget);
        expect(find.text('Phone speaker or wired'), findsOneWidget);
        expect(delaySlider(tester).value, ms.toDouble());
        d.dispose();
      });
    }
    testWidgets('the slider covers 0 to 600 ms in 10 ms steps', (tester) async {
      final (_, d) = await setup({});
      await tester.pumpWidget(_app(card(d)));
      await openDelay(tester);
      final slider = delaySlider(tester);
      expect(slider.min, 0);
      expect(slider.max, 600);
      expect(slider.divisions, 60);
      d.dispose();
    });
    testWidgets('sliding saves the new delay', (tester) async {
      final (s, d) = await setup({});
      await tester.pumpWidget(_app(card(d)));
      await openDelay(tester);
      delaySlider(tester).onChanged!(250.4);
      await tester.pump();
      expect(s.delayMs(bluetooth: false), 250);
      expect(find.text('250 ms'), findsOneWidget);
      d.dispose();
    });
    testWidgets('shows the Bluetooth speaker and its delay', (tester) async {
      _mockNative((call) async =>
          call.method == 'audioOutput' ? {'bluetooth': true, 'name': 'Boom'} : null);
      final (_, d) = await setup({'delay_bt': 220});
      await tester.pumpWidget(_app(card(d)));
      await tester.pump();
      await openDelay(tester);
      expect(find.text('Bluetooth: Boom'), findsOneWidget);
      expect(find.text('220 ms'), findsOneWidget);
      expect(find.byIcon(Icons.bluetooth_audio), findsOneWidget);
      d.dispose();
    });
  });

  group('SpeakerPulse', () {
    for (final size in [40.0, 72.0, 100.0]) {
      testWidgets('takes 1.8 times its size ($size)', (tester) async {
        await tester.pumpWidget(_app(SpeakerPulse(playing: false, size: size)));
        expect(tester.getSize(find.byType(SpeakerPulse)), Size(size * 1.8, size * 1.8));
      });
    }
    testWidgets('animates only while playing', (tester) async {
      await tester.pumpWidget(_app(const SpeakerPulse(playing: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(_app(const SpeakerPulse(playing: false)));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(_app(const SpeakerPulse(playing: true)));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('confirmLeave', () {
    for (final (button, result) in [('Stay', false), ('End party', true)]) {
      testWidgets('tapping $button returns $result', (tester) async {
        bool? got;
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => got = await confirmLeave(context,
                  title: 'End the party?', body: 'Music stops.', action: 'End party'),
              child: const Text('open'),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('End the party?'), findsOneWidget);
        expect(find.text('Music stops.'), findsOneWidget);
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(got, result);
      });
    }
    testWidgets('dismissing the dialog counts as stay', (tester) async {
      bool? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                got = await confirmLeave(context, title: 'T', body: 'B', action: 'Go'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(got, isFalse);
    });
  });

  group('BluetoothHelpScreen', () {
    final cases = <String, (Map<String, Object?>?, bool, bool, bool)>{
      // (reply, samsung way, auracast available, auracast unavailable)
      'no native side': (null, false, false, true),
      'Samsung with Auracast': ({'maker': 'Samsung', 'leAudioBroadcast': true}, true, true, false),
      'Samsung without Auracast': ({'maker': 'samsung', 'leAudioBroadcast': false}, true, false, true),
      'Pixel with Auracast': ({'maker': 'Google', 'leAudioBroadcast': true}, false, true, false),
      'other phone': ({'maker': 'xiaomi'}, false, false, true),
    };
    cases.forEach((what, c) {
      testWidgets(what, (tester) async {
        _mockNative((call) async => call.method == 'bluetoothFeatures' ? c.$1 : null);
        await tester.pumpWidget(const MaterialApp(home: BluetoothHelpScreen()));
        await tester.pump();
        expect(find.text('Many speakers, one phone'), findsOneWidget);
        expect(find.text('Dual audio: your phone has it'), c.$2 ? findsOneWidget : findsNothing);
        expect(find.text('Dual audio (Samsung phones)'), c.$2 ? findsNothing : findsOneWidget);
        expect(find.text('Audio sharing (Auracast): your phone has it'),
            c.$3 ? findsOneWidget : findsNothing);
        expect(find.text('Audio sharing (Auracast)'), c.$4 ? findsOneWidget : findsNothing);
      });
    });
    testWidgets('the Auracast button opens Bluetooth settings', (tester) async {
      final calls = <String>[];
      _mockNative((call) async {
        calls.add(call.method);
        return call.method == 'bluetoothFeatures'
            ? {'maker': 'Google', 'leAudioBroadcast': true}
            : null;
      });
      await tester.pumpWidget(const MaterialApp(home: BluetoothHelpScreen()));
      await tester.pump();
      await tester.ensureVisible(find.text('Bluetooth settings'));
      await tester.tap(find.text('Bluetooth settings'));
      await tester.pump();
      expect(calls, contains('openBluetoothSettings'));
    });
  });
}
