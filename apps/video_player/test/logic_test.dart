import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/format.dart';
import 'package:video_player_app/src/library/private_vault.dart';
import 'package:video_player_app/src/library/subtitles.dart';
import 'package:video_player_app/src/library/video_library.dart';
import 'package:video_player_app/src/player/play_item.dart';
import 'package:video_player_app/src/settings.dart';

VideoEntry _video(String id, String title,
    {int seconds = 60, int size = 0, int modified = 0}) {
  final v = VideoEntry(
    AssetEntity(
      id: id,
      typeInt: AssetType.video.index,
      width: 1920,
      height: 1080,
      duration: seconds,
      title: title,
      modifiedDateSecond: modified,
      relativePath: 'Movies/Trip/',
    ),
    'Trip',
  );
  v.size = size;
  return v;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('format', () {
    test('durations', () {
      expect(formatDuration(const Duration(seconds: 75)), '1:15');
      expect(formatDuration(const Duration(seconds: 3725)), '1:02:05');
      expect(formatDuration(const Duration(seconds: -12)), '-0:12');
    });

    test('sizes', () {
      expect(formatSize(0), '');
      expect(formatSize(740 * 1024), '740 KB');
      expect(formatSize((12.4 * 1024 * 1024).round()), '12.4 MB');
      expect(formatSize((1.27 * 1024 * 1024 * 1024).round()), '1.27 GB');
    });

    test('quality and speed', () {
      expect(qualityLabel(1920, 1080), '1080p');
      expect(qualityLabel(1080, 1920), '1080p');
      expect(qualityLabel(3840, 2160), '4K');
      expect(qualityLabel(0, 0), '');
      expect(formatSpeed(1), '1x');
      expect(formatSpeed(0.25), '0.25x');
      expect(formatSpeed(1.5), '1.5x');
    });
  });

  test('subtitle candidates sit next to the video', () {
    final c = sidecarCandidates('/storage/emulated/0/Movies/My.Film.mkv');
    expect(c.first, '/storage/emulated/0/Movies/My.Film.srt');
    expect(c, contains('/storage/emulated/0/Movies/My.Film.en.srt'));
  });

  test('video path is built from the media store folder', () {
    expect(_video('1', 'a.mp4').path, '/storage/emulated/0/Movies/Trip/a.mp4');
  });

  test('sorting videos', () {
    final vids = [
      _video('1', 'b.mp4', seconds: 30, size: 300, modified: 2),
      _video('2', 'A.mp4', seconds: 90, size: 100, modified: 3),
      _video('3', 'c.mp4', seconds: 60, size: 200, modified: 1),
    ];
    List<String> ids(VideoSort s, bool desc) =>
        VideoLibrary.sortVideos(vids, s, desc).map((v) => v.id).toList();
    expect(ids(VideoSort.name, false), ['2', '1', '3']);
    expect(ids(VideoSort.size, true), ['1', '3', '2']);
    expect(ids(VideoSort.duration, false), ['1', '3', '2']);
    expect(ids(VideoSort.date, true), ['2', '1', '3']);
  });

  test('play items from links and other apps', () {
    expect(PlayItem.fromUrl('https://x.com/media/My%20Clip.mp4').title,
        'My Clip.mp4');
    expect(PlayItem.fromUrl('https://x.com/').title, 'x.com');
    final ext = PlayItem.fromExternal('file:///sdcard/Download/show.mkv');
    expect(ext.title, 'show.mkv');
    expect(ext.path, '/sdcard/Download/show.mkv');
    final v = PlayItem.fromEntry(_video('42', 'a.mp4'));
    expect(v.uri, 'content://media/external/video/media/42');
    expect(v.key, '42');
  });

  group('settings', () {
    late Settings s;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      s = await Settings.open();
    });

    test('resume points', () {
      const d = Duration(minutes: 10);
      s.savePosition('a', const Duration(minutes: 3), d);
      expect(s.positionFor('a'), const Duration(minutes: 3));
      expect(s.progressFor('a', d), closeTo(0.3, 0.001));
      // Near the end counts as finished: start over next time.
      s.savePosition('a', const Duration(minutes: 9, seconds: 58), d);
      expect(s.positionFor('a'), Duration.zero);
      // Barely started: nothing to resume.
      s.savePosition('b', const Duration(seconds: 2), d);
      expect(s.positionFor('b'), isNull);
    });

    test('recents keep newest first without duplicates', () async {
      s.addRecent(RecentItem(key: 'a', title: 'A', uri: 'u'));
      s.addRecent(RecentItem(key: 'b', title: 'B', uri: 'u'));
      s.addRecent(RecentItem(key: 'a', title: 'A', uri: 'u'));
      expect(s.recents.map((r) => r.key), ['a', 'b']);
      final again = await Settings.open();
      expect(again.recents.map((r) => r.key), ['a', 'b']);
    });

    test('PIN is stored hashed and checked', () {
      final vault = PrivateVault(s);
      expect(vault.hasPin, isFalse);
      vault.setPin('1234');
      expect(vault.hasPin, isTrue);
      expect(s.pinHash, isNot(contains('1234')));
      expect(vault.checkPin('1234'), isTrue);
      expect(vault.checkPin('4321'), isFalse);
    });
  });
}
