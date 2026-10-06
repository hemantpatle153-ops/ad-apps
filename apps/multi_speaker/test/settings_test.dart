import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_speaker/src/platform/native.dart';
import 'package:multi_speaker/src/settings.dart';
import 'package:multi_speaker/src/speaker_delay.dart';
import 'package:multi_speaker/src/ui/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/gen.dart';

const _channel = MethodChannel('in.onlysoftware.multi_speaker/native');

Future<Settings> _settings([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return Settings.load();
}

void _mockNative(Future<Object?>? Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => _mockNative(null));

  group('formatTime', () {
    const table = <int, String>{
      0: '0:00',
      1: '0:01',
      9: '0:09',
      10: '0:10',
      59: '0:59',
      60: '1:00',
      61: '1:01',
      119: '1:59',
      600: '10:00',
      3599: '59:59',
      3600: '60:00',
      5999: '99:59',
      6000: '100:00',
    };
    table.forEach((s, text) {
      test('$s s reads $text', () => expect(formatTime(Duration(seconds: s)), text));
    });
    final r = Random(1);
    for (var i = 0; i < 60; i++) {
      final ms = r.nextInt(4 * 3600 * 1000);
      test('#$i ${ms}ms shows whole minutes and padded seconds', () {
        final text = formatTime(Duration(milliseconds: ms));
        final parts = text.split(':');
        expect(parts, hasLength(2));
        expect(int.parse(parts[0]), ms ~/ 60000);
        expect(parts[1], hasLength(2));
        expect(int.parse(parts[1]), (ms ~/ 1000) % 60);
      });
    }
    for (final ms in [1, 499, 500, 999]) {
      test('$ms ms rounds down to 0:00', () {
        expect(formatTime(Duration(milliseconds: ms)), '0:00');
      });
    }
  });

  group('Settings speaker delay', () {
    test('defaults: phone 0 ms, Bluetooth 200 ms', () async {
      final s = await _settings();
      expect(s.delayMs(bluetooth: false), 0);
      expect(s.delayMs(bluetooth: true), Settings.defaultBluetoothDelayMs);
      expect(Settings.defaultBluetoothDelayMs, 200);
    });
    final values = [
      -100000, -601, -1, 0, 1, 5, 10, 99, 150, 199, 200, 201, 250, 300, 333,
      450, 599, 600, 601, 700, 1000, 99999,
    ];
    for (final bt in [false, true]) {
      for (final v in values) {
        final expected = v.clamp(0, Settings.maxDelayMs);
        test('${bt ? 'Bluetooth' : 'phone'} delay set to $v reads $expected', () async {
          final s = await _settings();
          s.setDelayMs(v, bluetooth: bt);
          expect(s.delayMs(bluetooth: bt), expected);
          // The other output keeps its own value.
          expect(s.delayMs(bluetooth: !bt), bt ? 0 : Settings.defaultBluetoothDelayMs);
          // And it is saved.
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getInt(bt ? 'delay_bt' : 'delay_phone'), expected);
        });
      }
    }
    final r = Random(2);
    for (var i = 0; i < 20; i++) {
      final phone = r.nextInt(Settings.maxDelayMs + 1);
      final bt = r.nextInt(Settings.maxDelayMs + 1);
      test('#$i saved values phone=$phone bt=$bt are read back', () async {
        final s = await _settings({'delay_phone': phone, 'delay_bt': bt});
        expect(s.delayMs(bluetooth: false), phone);
        expect(s.delayMs(bluetooth: true), bt);
      });
    }
    for (final bt in [false, true]) {
      test('setting the ${bt ? 'Bluetooth' : 'phone'} delay notifies listeners once', () async {
        final s = await _settings();
        var n = 0;
        s.addListener(() => n++);
        s.setDelayMs(123, bluetooth: bt);
        expect(n, 1);
      });
    }
  });

  group('Settings name', () {
    const cases = <String?, String?>{
      null: null,
      '': null,
      ' ': null,
      '\t\n': null,
      'Asha': 'Asha',
      '  Asha  ': 'Asha',
      '\tKitchen speaker\n': 'Kitchen speaker',
      'a b': 'a b',
      "Rahul's phone": "Rahul's phone",
      '🎉': '🎉',
      'पार्टी ': 'पार्टी',
    };
    cases.forEach((input, stored) {
      test('setting ${input == null ? 'null' : '"${input.replaceAll('\n', r'\n').replaceAll('\t', r'\t')}"'} stores ${stored == null ? 'nothing' : '"$stored"'}', () async {
        final s = await _settings({'name': 'Old'});
        var n = 0;
        s.addListener(() => n++);
        s.name = input;
        expect(s.name, stored);
        expect(n, 1);
      });
    });
    for (final name in trickyNames.where((n) => n.trim().isNotEmpty)) {
      test('name "$name" is kept trimmed', () async {
        final s = await _settings();
        s.name = name;
        expect(s.name, name.trim());
      });
    }
    test('no name saved reads null', () async {
      expect((await _settings()).name, isNull);
    });
  });

  group('Settings seenIntro', () {
    test('false by default', () async {
      expect((await _settings()).seenIntro, isFalse);
    });
    for (final v in [true, false]) {
      test('set to $v reads $v and is saved', () async {
        final s = await _settings({'seen_intro': !v});
        s.seenIntro = v;
        expect(s.seenIntro, v);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('seen_intro'), v);
      });
    }
  });

  group('Native without the Android side', () {
    test('audioOutput falls back to the phone speaker', () async {
      final o = await Native.audioOutput();
      expect(o.bluetooth, isFalse);
      expect(o.name, isNull);
    });
    test('deviceName falls back to "Phone"', () async {
      expect(await Native.deviceName(), 'Phone');
    });
    test('bluetoothFeatures reports nothing special', () async {
      final f = await Native.bluetoothFeatures();
      expect(f.leAudioBroadcast, isFalse);
      expect(f.maker, '');
    });
    for (final m in ['holdNetwork', 'releaseNetwork']) {
      test('holdNetwork(${m == 'holdNetwork'}) completes', () async {
        await Native.holdNetwork(m == 'holdNetwork');
      });
    }
    test('openBluetoothSettings completes', () => Native.openBluetoothSettings());
    test('openHotspotSettings completes', () => Native.openHotspotSettings());
  });

  group('Native with the Android side', () {
    final outputs = <String, (Object?, Object?, bool, String?)>{
      'Bluetooth with a name': (true, 'JBL Flip', true, 'JBL Flip'),
      'Bluetooth without a name': (true, null, true, null),
      'wired': (false, null, false, null),
      'phone with a stray name': (false, 'X', false, 'X'),
      'bluetooth as text': ('true', 'Y', false, 'Y'),
      'bluetooth as 1': (1, null, false, null),
      'bluetooth missing': (null, 'Z', false, 'Z'),
      'unicode name': (true, 'Boîte 🎵', true, 'Boîte 🎵'),
    };
    outputs.forEach((what, c) {
      test('audioOutput: $what', () async {
        _mockNative((call) async {
          expect(call.method, 'audioOutput');
          return {'bluetooth': c.$1, 'name': c.$2};
        });
        final o = await Native.audioOutput();
        expect(o.bluetooth, c.$3);
        expect(o.name, c.$4);
      });
    });
    test('audioOutput: a platform error falls back to the phone', () async {
      _mockNative((call) async => throw PlatformException(code: 'x'));
      expect((await Native.audioOutput()).bluetooth, isFalse);
    });
    for (final name in ['Pixel 8', 'SM-S921B', 'Asha’s phone', '']) {
      test('deviceName returns "$name"', () async {
        _mockNative((call) async => call.method == 'deviceName' ? name : null);
        expect(await Native.deviceName(), name);
      });
    }
    test('deviceName: a platform error falls back to "Phone"', () async {
      _mockNative((call) async => throw PlatformException(code: 'x'));
      expect(await Native.deviceName(), 'Phone');
    });
    final features = <String, (Object?, Object?, bool, String)>{
      'Samsung with LE audio': (true, 'samsung', true, 'samsung'),
      'upper-case maker is lowered': (false, 'SAMSUNG', false, 'samsung'),
      'mixed-case maker': (true, 'Google', true, 'google'),
      'missing maker': (true, null, true, ''),
      'leAudio as text is not true': ('true', 'xiaomi', false, 'xiaomi'),
      'nothing': (null, null, false, ''),
    };
    features.forEach((what, c) {
      test('bluetoothFeatures: $what', () async {
        _mockNative((call) async {
          expect(call.method, 'bluetoothFeatures');
          return {'leAudioBroadcast': c.$1, 'maker': c.$2};
        });
        final f = await Native.bluetoothFeatures();
        expect(f.leAudioBroadcast, c.$3);
        expect(f.maker, c.$4);
      });
    });
    for (final on in [true, false]) {
      test('holdNetwork($on) calls ${on ? 'holdNetwork' : 'releaseNetwork'}', () async {
        final calls = <String>[];
        _mockNative((call) async {
          calls.add(call.method);
          return null;
        });
        await Native.holdNetwork(on);
        expect(calls, [on ? 'holdNetwork' : 'releaseNetwork']);
      });
    }
    for (final (method, run) in [
      ('openBluetoothSettings', Native.openBluetoothSettings),
      ('openHotspotSettings', Native.openHotspotSettings),
    ]) {
      test('$method reaches the Android side', () async {
        final calls = <String>[];
        _mockNative((call) async {
          calls.add(call.method);
          return null;
        });
        await run();
        expect(calls, [method]);
      });
    }
  });

  group('SpeakerDelay', () {
    final outputs = <(bool, String?), String>{
      (false, null): 'Phone speaker or wired',
      (true, null): 'Bluetooth',
      (true, 'JBL Flip 6'): 'Bluetooth: JBL Flip 6',
      (true, 'Car'): 'Bluetooth: Car',
      (true, ''): 'Bluetooth: ',
    };
    outputs.forEach((o, label) {
      test('output bluetooth=${o.$1} name=${o.$2} is labelled "$label"', () async {
        _mockNative((call) async =>
            call.method == 'audioOutput' ? {'bluetooth': o.$1, 'name': o.$2} : null);
        final d = SpeakerDelay(await _settings());
        await _settle();
        expect(d.output.bluetooth, o.$1);
        expect(d.outputLabel, label);
        d.dispose();
      });
    });

    for (final bt in [false, true]) {
      for (final ms in [0, 40, 200, 380, 600, 900, -5]) {
        test('on ${bt ? 'Bluetooth' : 'the phone'} setting $ms ms changes only that delay', () async {
          _mockNative((call) async =>
              call.method == 'audioOutput' ? {'bluetooth': bt} : null);
          final s = await _settings();
          final d = SpeakerDelay(s);
          await _settle();
          d.ms = ms;
          final clamped = ms.clamp(0, Settings.maxDelayMs);
          expect(d.ms, clamped);
          expect(d.latencyUs(), clamped * 1000);
          expect(s.delayMs(bluetooth: bt), clamped);
          expect(s.delayMs(bluetooth: !bt), bt ? 0 : Settings.defaultBluetoothDelayMs);
          d.dispose();
        });
      }
    }

    test('starts on the phone speaker and its delay', () async {
      final d = SpeakerDelay(await _settings({'delay_phone': 30, 'delay_bt': 250}));
      expect(d.output.bluetooth, isFalse);
      expect(d.ms, 30);
      expect(d.latencyUs(), 30000);
      d.dispose();
    });

    test('switching to Bluetooth switches to its delay and notifies', () async {
      _mockNative((call) async =>
          call.method == 'audioOutput' ? {'bluetooth': true, 'name': 'Boom'} : null);
      final d = SpeakerDelay(await _settings({'delay_phone': 30, 'delay_bt': 250}));
      var n = 0;
      d.addListener(() => n++);
      await _settle();
      expect(n, 1);
      expect(d.ms, 250);
      d.dispose();
    });

    test('an unchanged output does not notify', () async {
      final d = SpeakerDelay(await _settings());
      var n = 0;
      d.addListener(() => n++);
      await _settle();
      expect(n, 0);
      d.dispose();
    });

    test('settings changes are passed on to listeners', () async {
      final s = await _settings();
      final d = SpeakerDelay(s);
      await _settle();
      var n = 0;
      d.addListener(() => n++);
      s.setDelayMs(50, bluetooth: true);
      s.name = 'x';
      expect(n, 2);
      d.dispose();
      s.setDelayMs(60, bluetooth: true);
      expect(n, 2, reason: 'no longer listening after dispose');
    });
  });
}
