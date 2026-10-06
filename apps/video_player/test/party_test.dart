import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/party/protocol.dart';
import 'package:video_player_app/src/player/effects.dart';
import 'package:video_player_app/src/settings.dart';

void main() {
  group('parseRange', () {
    test('reads normal, open-ended and suffix ranges', () {
      expect(parseRange('bytes=0-99', 1000), (0, 99));
      expect(parseRange('bytes=500-', 1000), (500, 999));
      expect(parseRange('bytes=-100', 1000), (900, 999));
      expect(parseRange('bytes=900-5000', 1000), (900, 999));
    });

    test('rejects ranges it cannot serve', () {
      expect(parseRange(null, 1000), isNull);
      expect(parseRange('bytes=1000-', 1000), isNull);
      expect(parseRange('bytes=50-10', 1000), isNull);
      expect(parseRange('bytes=0-1,5-9', 1000), isNull);
      expect(parseRange('items=0-1', 1000), isNull);
    });
  });

  test('PartyState moves forward only while playing, at its rate', () {
    const paused = PartyState(playing: false, positionUs: 5000000, anchorUs: 0);
    expect(paused.positionAt(99000000), 5000000);
    const playing =
        PartyState(playing: true, positionUs: 1000000, anchorUs: 2000000, rate: 2);
    expect(playing.positionAt(3000000), 3000000);
    final round = PartyState.fromJson(playing.toJson());
    expect(round.positionAt(3000000), 3000000);
  });

  group('JoinCode', () {
    test('survives a QR round trip', () {
      const code = JoinCode(hosts: ['192.168.1.5', '10.0.0.2'], port: 47810, name: 'Rahul');
      final back = JoinCode.parse(code.encode())!;
      expect(back.hosts, code.hosts);
      expect(back.port, 47810);
      expect(back.name, 'Rahul');
    });

    test('accepts a typed address', () {
      expect(JoinCode.parse(' 192.168.43.1 ')!.port, partyPort);
      expect(JoinCode.parse('192.168.43.1:5000')!.port, 5000);
      expect(JoinCode.parse('300.1.1.1'), isNull);
      expect(JoinCode.parse('hello'), isNull);
    });
  });

  test('audioFilter builds an mpv filter only when needed', () {
    expect(audioFilter(List.filled(10, 0), night: false), '');
    final f = audioFilter([6, 0, 0, 0, 0, 0, 0, 0, 0, -3], night: true);
    expect(f, startsWith('lavfi=['));
    expect(f, contains('equalizer=f=31:width_type=o:width=1:g=6.0'));
    expect(f, contains('equalizer=f=16000:width_type=o:width=1:g=-3.0'));
    expect(f, contains('dynaudnorm'));
  });

  test('bookmarks are sorted, removable and saved', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.open();
    s.addBookmark('v', const Duration(seconds: 30));
    s.addBookmark('v', const Duration(seconds: 10));
    expect(s.bookmarksFor('v'), [const Duration(seconds: 10), const Duration(seconds: 30)]);
    s.removeBookmark('v', const Duration(seconds: 10));
    final again = await Settings.open();
    expect(again.bookmarksFor('v'), [const Duration(seconds: 30)]);
    expect(again.bookmarksFor('other'), isEmpty);
  });
}
