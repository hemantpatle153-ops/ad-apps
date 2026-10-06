import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player_app/src/library/video_library.dart';
import 'package:video_player_app/src/party/online.dart';
import 'package:video_player_app/src/party/pick_video_screen.dart';

VideoEntry _video(String id, String title, int seconds) => VideoEntry(
      AssetEntity(
        id: id,
        typeInt: AssetType.video.index,
        width: 1920,
        height: 1080,
        duration: seconds,
        title: title,
      ),
      'Movies',
    );

void main() {
  test('room codes use only easy-to-read characters', () {
    final rng = Random(1);
    for (var i = 0; i < 200; i++) {
      final code = newRoomCode(rng);
      expect(code.length, 6);
      expect(code, isNot(matches(RegExp('[01OIL]'))));
      expect(normalizeRoomCode(code), code);
    }
  });

  test('typed codes are cleaned up or rejected', () {
    expect(normalizeRoomCode(' k7q-f2m '), 'K7QF2M');
    expect(normalizeRoomCode('K7QF2'), isNull);
    expect(normalizeRoomCode('K7QF2O'), isNull);
  });

  test('online video survives the database round trip', () {
    const v = OnlineVideo(title: 'Movie', url: 'https://x/a.m3u8', durationMs: 5000);
    final back = OnlineVideo.fromJson(v.toJson());
    expect(back.title, 'Movie');
    expect(back.isLink, isTrue);
    expect(back.durationMs, 5000);
    expect(OnlineVideo.fromJson({'title': 'File'}).isLink, isFalse);
  });

  test('the matching video is ranked first', () {
    final videos = [
      _video('1', 'holiday.mp4', 300),
      _video('2', 'movie copy.mkv', 7201),
      _video('3', 'movie.mkv', 60),
    ];
    const target = OnlineVideo(title: 'movie.mkv', durationMs: 7200000);
    expect(rankMatches(videos, target).first.id, '2');
    expect(sameLength(const Duration(seconds: 7201), 7200000), isTrue);
    expect(sameLength(const Duration(seconds: 60), 7200000), isFalse);
  });
}
