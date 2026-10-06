import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/library/private_vault.dart';
import 'package:video_player_app/src/player/system_channel.dart';
import 'package:video_player_app/src/settings.dart';

const _system = MethodChannel('in.onlysoftware.video_player/system');
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

Future<void> platformCalls(String method, Object? args) async {
  final data =
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_system.name, data, (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('hashPin', () {
    final r = Random(4);
    final pins = <String>{};
    while (pins.length < 30) {
      pins.add(r.nextInt(10000).toString().padLeft(4, '0'));
    }
    for (final pin in pins) {
      test('pin $pin hashes deterministically to sha256 hex', () {
        final a = PrivateVault.hashPin('salt', pin);
        expect(a, PrivateVault.hashPin('salt', pin));
        expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(a, isNot(contains(pin)));
        expect(PrivateVault.hashPin('other', pin), isNot(a));
      });
    }
    test('salt and pin are separated', () {
      expect(PrivateVault.hashPin('12', '34'),
          isNot(PrivateVault.hashPin('1', '234')));
    });
    for (final (salt, pin, hex) in [
      (
        's',
        '1234',
        '663e504d0f9c7f45da38f1fc40ca8c18dd1abe4614f49333762cc02ba8b47c97'
      ),
      (
        'abc',
        '0000',
        'dce4ce5ef48a8bd6f025c188ac9fedb595fa6707151a67870e079caa674fc2e9'
      ),
    ]) {
      test('known vector sha256("$salt:$pin")', () {
        expect(PrivateVault.hashPin(salt, pin), hex);
      });
    }
  });

  group('PIN set and check', () {
    final r = Random(8);
    for (var i = 0; i < 30; i++) {
      final pin = r.nextInt(10000).toString().padLeft(4, '0');
      final wrong = ((int.parse(pin) + 1 + r.nextInt(9998)) % 10000)
          .toString()
          .padLeft(4, '0');
      test('vault #$i accepts $pin and rejects $wrong', () async {
        SharedPreferences.setMockInitialValues({});
        final s = await Settings.open();
        final vault = PrivateVault(s);
        var n = 0;
        vault.addListener(() => n++);
        expect(vault.checkPin(pin), isFalse);
        vault.setPin(pin);
        expect(n, 1);
        expect(vault.hasPin, isTrue);
        expect(vault.checkPin(pin), isTrue);
        expect(vault.checkPin(wrong), isFalse);
        expect(vault.checkPin(''), isFalse);
        expect(s.pinHash, PrivateVault.hashPin(s.pinSalt!, pin));
        expect(base64Url.decode(s.pinSalt!).length, 16);
        // A reopened settings object still validates the PIN.
        expect(PrivateVault(await Settings.open()).checkPin(pin), isTrue);
      });
    }
    test('each setPin uses a fresh salt', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.open();
      final vault = PrivateVault(s);
      final salts = <String>{};
      for (var i = 0; i < 10; i++) {
        vault.setPin('1111');
        salts.add(s.pinSalt!);
      }
      expect(salts.length, 10);
    });
    test('hash without salt never matches', () async {
      SharedPreferences.setMockInitialValues(
          {'pinHash': PrivateVault.hashPin('', '1234')});
      expect(PrivateVault(await Settings.open()).checkPin('1234'), isFalse);
    });
  });

  group('vault folder on disk', () {
    late Directory base;
    late Settings s;
    setUp(() async {
      base = await Directory.systemTemp.createTemp('vault');
      messenger.setMockMethodCallHandler(
          _pathProvider, (call) async => base.path);
      SharedPreferences.setMockInitialValues({});
      s = await Settings.open();
    });
    tearDown(() async {
      messenger.setMockMethodCallHandler(_pathProvider, null);
      if (await base.exists()) await base.delete(recursive: true);
    });

    test('load lists files with their original folders, skipping the index',
        () async {
      final dir = Directory('${base.path}/private')..createSync();
      File('${dir.path}/a.mp4').writeAsBytesSync(List.filled(10, 1));
      File('${dir.path}/b.mkv').writeAsBytesSync(List.filled(25, 1));
      File('${dir.path}/index.json')
          .writeAsStringSync(jsonEncode({'a.mp4': 'DCIM/Camera/'}));
      final vault = PrivateVault(s);
      await vault.load();
      final byName = {for (final v in vault.videos) v.title: v};
      expect(byName.keys.toSet(), {'a.mp4', 'b.mkv'});
      expect(byName['a.mp4']!.originalFolder, 'DCIM/Camera/');
      expect(byName['b.mkv']!.originalFolder, 'Movies/');
      expect(byName['a.mp4']!.size, 10);
      expect(byName['b.mkv']!.size, 25);
    });

    test('corrupt index falls back to Movies/', () async {
      final dir = Directory('${base.path}/private')..createSync();
      File('${dir.path}/a.mp4').writeAsStringSync('x');
      File('${dir.path}/index.json').writeAsStringSync('{oops');
      final vault = PrivateVault(s);
      await vault.load();
      expect(vault.videos.single.originalFolder, 'Movies/');
    });

    test('deleteForever removes the file', () async {
      final vault = PrivateVault(s);
      await vault.load();
      expect(vault.videos, isEmpty);
      File('${base.path}/private/gone.mp4').writeAsStringSync('x');
      await vault.load();
      await vault.deleteForever(vault.videos.single);
      expect(vault.videos, isEmpty);
      expect(File('${base.path}/private/gone.mp4').existsSync(), isFalse);
    });

    test('reset wipes files and PIN', () async {
      final vault = PrivateVault(s)..setPin('2580');
      await vault.load();
      File('${base.path}/private/a.mp4').writeAsStringSync('x');
      await vault.load();
      expect(vault.videos, hasLength(1));
      await vault.reset();
      expect(vault.videos, isEmpty);
      expect(vault.hasPin, isFalse);
      expect(Directory('${base.path}/private').existsSync(), isFalse);
      await vault.load();
      expect(Directory('${base.path}/private').existsSync(), isTrue);
    });
  });

  group('SystemChannel', () {
    final sys = SystemChannel.instance;
    final calls = <MethodCall>[];
    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(_system, (call) async {
        calls.add(call);
        return switch (call.method) {
          'pipSupported' => true,
          'enterPip' => true,
          'takeOpenedUri' => 'file:///sdcard/opened.mp4',
          _ => null,
        };
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(_system, null));

    for (final v in [true, false, true, null, 'yes', 1]) {
      test('pipChanged($v) sets inPip=${v == true}', () async {
        await platformCalls('pipChanged', v);
        expect(sys.inPip.value, v == true);
      });
    }

    test('openUri is delivered once even if pushed twice quickly', () async {
      final got = <String>[];
      sys.onOpenUri = got.add;
      addTearDown(() => sys.onOpenUri = null);
      await platformCalls('openUri', 'content://x/1');
      await platformCalls('openUri', 'content://x/1');
      await platformCalls('openUri', null);
      await platformCalls('openUri', 'content://x/2');
      await platformCalls('openUri', 'content://x/1');
      expect(got, ['content://x/1', 'content://x/2', 'content://x/1']);
    });

    test('takeOpenedUri pulls the launch uri', () async {
      final got = <String>[];
      sys.onOpenUri = got.add;
      addTearDown(() => sys.onOpenUri = null);
      await sys.takeOpenedUri();
      expect(got, ['file:///sdcard/opened.mp4']);
      expect(calls.single.method, 'takeOpenedUri');
    });

    test('enterPip passes the video size', () async {
      expect(await sys.enterPip(1920, 1080), isTrue);
      expect(calls.single.method, 'enterPip');
      expect(calls.single.arguments, {'w': 1920, 'h': 1080});
    });

    test('setAutoPip passes enabled flag and size', () async {
      await sys.setAutoPip(true, null, 720);
      expect(calls.single.arguments, {'enabled': true, 'w': null, 'h': 720});
    });

    test('pipSupported asks once and caches', () async {
      expect(await sys.pipSupported(), isTrue);
      expect(await sys.pipSupported(), isTrue);
      expect(calls.where((c) => c.method == 'pipSupported').length, 1);
    });

    test('platform errors become false / no-ops', () async {
      messenger.setMockMethodCallHandler(_system, (call) async {
        throw PlatformException(code: 'x');
      });
      expect(await sys.enterPip(1, 1), isFalse);
      await sys.setAutoPip(false, 1, 1);
      await sys.moveToBack();
    });
  });
}
