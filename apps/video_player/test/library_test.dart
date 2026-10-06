import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/library/private_vault.dart';
import 'package:video_player_app/src/library/subtitles.dart';
import 'package:video_player_app/src/library/video_library.dart';
import 'package:video_player_app/src/player/play_item.dart';
import 'package:video_player_app/src/settings.dart';

import 'support/fixtures.dart';

void main() {
  group('VideoEntry.path', () {
    const cases = <(String?, String?), String?>{
      ('Movies/Trip/', 'a.mp4'): '/storage/emulated/0/Movies/Trip/a.mp4',
      ('Movies/Trip', 'a.mp4'): '/storage/emulated/0/Movies/Trip/a.mp4',
      ('DCIM/Camera/', 'VID_2024.mp4'):
          '/storage/emulated/0/DCIM/Camera/VID_2024.mp4',
      ('Download/', 'show s01e01.mkv'):
          '/storage/emulated/0/Download/show s01e01.mkv',
      ('WhatsApp/Media/WhatsApp Video/', 'x.mp4'):
          '/storage/emulated/0/WhatsApp/Media/WhatsApp Video/x.mp4',
      ('/storage/1234-ABCD/Movies', 'b.mkv'): '/storage/1234-ABCD/Movies/b.mkv',
      ('/storage/1234-ABCD/Movies/', 'b.mkv'):
          '/storage/1234-ABCD/Movies/b.mkv',
      ('/sdcard', 'c.avi'): '/sdcard/c.avi',
      (null, 'a.mp4'): null,
      ('Movies/', null): null,
      (null, null): null,
    };
    cases.forEach((input, expected) {
      test('rel=${input.$1} title=${input.$2} -> $expected', () {
        final v = makeVideo('1', relativePath: input.$1, title: input.$2);
        expect(v.path, expected);
      });
    });
  });

  group('VideoEntry getters', () {
    final r = Random(21);
    for (var i = 0; i < 40; i++) {
      final w = 100 + r.nextInt(4000), h = 100 + r.nextInt(4000);
      final orientation = const [0, 90, 180, 270][i % 4];
      final secs = r.nextInt(20000);
      final mod = 1500000000 + r.nextInt(200000000);
      final created = 1400000000 + r.nextInt(200000000);
      test('entry #$i ${w}x$h rot $orientation', () {
        final v = makeVideo('id$i',
            width: w,
            height: h,
            orientation: orientation,
            seconds: secs,
            modified: mod,
            created: created,
            folder: 'F$i',
            title: 't$i.mp4');
        final flipped = orientation == 90 || orientation == 270;
        expect(v.id, 'id$i');
        expect(v.title, 't$i.mp4');
        expect(v.folder, 'F$i');
        expect(v.width, flipped ? h : w);
        expect(v.height, flipped ? w : h);
        expect(v.duration, Duration(seconds: secs));
        expect(v.modified.millisecondsSinceEpoch, mod * 1000);
        expect(v.created.millisecondsSinceEpoch, created * 1000);
        expect(v.size, 0);
      });
    }
    test('missing title shows "Video"', () {
      expect(makeVideo('1', title: null).title, 'Video');
    });
  });

  group('VideoEntry.matches', () {
    const title = 'Holiday In GOA 2024.mp4';
    const table = {
      '': true,
      'holiday': true,
      'HOLIDAY': true,
      'goa': true,
      'In Goa': true,
      '2024': true,
      '.MP4': true,
      'y i': true,
      'holidays': false,
      'goa2024': false,
      'mkv': false,
      'xyz': false,
    };
    table.forEach((q, expected) {
      test('"$q" -> $expected', () {
        expect(makeVideo('1', title: title).matches(q), expected);
      });
    });
    final r = Random(3);
    for (var i = 0; i < 30; i++) {
      final t = randomWord(r, minLen: 5, maxLen: 20);
      final a = r.nextInt(t.length), b = a + 1 + r.nextInt(t.length - a);
      final sub = t.substring(a, b);
      test('random title "$t" matches its slice "$sub" in any case', () {
        final v = makeVideo('1', title: t);
        expect(v.matches(sub), isTrue);
        expect(v.matches(sub.toUpperCase()), isTrue);
        expect(v.matches(sub.toLowerCase()), isTrue);
        expect(v.matches('$t!'), isFalse);
      });
    }
  });

  group('VideoFolder aggregates', () {
    for (var seed = 0; seed < 25; seed++) {
      test('folder seed $seed sums size/duration and finds latest', () {
        final r = Random(seed);
        final n = r.nextInt(12);
        final vids = [
          for (var i = 0; i < n; i++)
            makeVideo('$i',
                size: r.nextInt(1 << 30),
                seconds: r.nextInt(10000),
                modified: 1000000 + r.nextInt(1000000000)),
        ];
        final f = VideoFolder('id', 'Name', vids);
        expect(f.totalSize, vids.fold<int>(0, (s, v) => s + v.size));
        expect(f.totalDuration.inSeconds,
            vids.fold<int>(0, (s, v) => s + v.duration.inSeconds));
        if (n == 0) {
          expect(f.latest.millisecondsSinceEpoch, 0);
        } else {
          final maxMod = vids
              .map((v) => v.modified)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          expect(f.latest, maxMod);
        }
      });
    }
  });

  group('sortVideos', () {
    for (var seed = 0; seed < 15; seed++) {
      final r = Random(1000 + seed);
      final vids = [
        for (var i = 0; i < 3 + r.nextInt(25); i++)
          makeVideo('v$i',
              title: '${randomWord(r)}.mp4',
              seconds: r.nextInt(5000),
              size: r.nextInt(1 << 31),
              modified: r.nextInt(1 << 30)),
      ];
      for (final sort in VideoSort.values) {
        for (final desc in [false, true]) {
          test('seed $seed by ${sort.name} ${desc ? 'desc' : 'asc'}', () {
            final input = [...vids];
            final out = VideoLibrary.sortVideos(input, sort, desc);
            expect(input.map((v) => v.id), vids.map((v) => v.id),
                reason: 'input untouched');
            expect(out.map((v) => v.id).toSet(), vids.map((v) => v.id).toSet());
            expect(out.length, vids.length);
            int cmp(VideoEntry a, VideoEntry b) => switch (sort) {
                  VideoSort.name =>
                    a.title.toLowerCase().compareTo(b.title.toLowerCase()),
                  VideoSort.date => a.modified.compareTo(b.modified),
                  VideoSort.size => a.size.compareTo(b.size),
                  VideoSort.duration => a.duration.compareTo(b.duration),
                };
            for (var i = 1; i < out.length; i++) {
              final c = cmp(out[i - 1], out[i]);
              expect(desc ? c >= 0 : c <= 0, isTrue, reason: 'at $i');
            }
          });
        }
      }
    }
    test('empty list stays empty', () {
      for (final s in VideoSort.values) {
        expect(VideoLibrary.sortVideos(const [], s, true), isEmpty);
      }
    });
    test('name sort ignores case', () {
      final out = VideoLibrary.sortVideos([
        makeVideo('1', title: 'beta'),
        makeVideo('2', title: 'Alpha'),
        makeVideo('3', title: 'GAMMA')
      ], VideoSort.name, false);
      expect(out.map((v) => v.title), ['Alpha', 'beta', 'GAMMA']);
    });
  });

  group('sortFolders', () {
    for (var seed = 0; seed < 12; seed++) {
      final r = Random(2000 + seed);
      final folders = [
        for (var i = 0; i < 2 + r.nextInt(10); i++)
          VideoFolder('f$i', randomWord(r), [
            for (var j = 0; j < r.nextInt(8); j++)
              makeVideo('f$i-$j', modified: r.nextInt(1 << 30)),
          ]),
      ];
      for (final sort in FolderSort.values) {
        test('seed $seed by ${sort.name}', () {
          final out = VideoLibrary.sortFolders(folders, sort);
          expect(
              out.map((f) => f.id).toSet(), folders.map((f) => f.id).toSet());
          for (var i = 1; i < out.length; i++) {
            final a = out[i - 1], b = out[i];
            switch (sort) {
              case FolderSort.name:
                expect(a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    lessThanOrEqualTo(0));
              case FolderSort.count:
                expect(a.videos.length, greaterThanOrEqualTo(b.videos.length));
              case FolderSort.date:
                expect(a.latest.isBefore(b.latest), isFalse);
            }
          }
        });
      }
    }
  });

  group('VideoLibrary lookups', () {
    late List<VideoFolder> saved;
    setUp(() => saved = VideoLibrary.instance.folders);
    tearDown(() => VideoLibrary.instance.folders = saved);

    for (var seed = 0; seed < 10; seed++) {
      test('byId/all over random folders seed $seed', () {
        final r = Random(seed);
        var next = 0;
        final folders = [
          for (var i = 0; i < 1 + r.nextInt(5); i++)
            VideoFolder('f$i', 'F$i', [
              for (var j = 0; j < r.nextInt(6); j++)
                makeVideo('${next++}', folder: 'F$i'),
            ]),
        ];
        VideoLibrary.instance.folders = folders;
        final all = VideoLibrary.instance.all;
        expect(all.length, next);
        expect(all.map((v) => v.id), [for (var i = 0; i < next; i++) '$i']);
        for (final v in all) {
          expect(identical(VideoLibrary.instance.byId(v.id), v), isTrue);
        }
        expect(VideoLibrary.instance.byId('missing'), isNull);
        expect(VideoLibrary.instance.byId(''), isNull);
      });
    }
  });

  group('sidecarCandidates', () {
    const table = {
      '/storage/emulated/0/Movies/My.Film.mkv':
          '/storage/emulated/0/Movies/My.Film',
      '/sdcard/a.mp4': '/sdcard/a',
      '/sdcard/no_extension': '/sdcard/no_extension',
      '/sdcard/my.folder/clip': '/sdcard/my.folder/clip',
      '/sdcard/my.folder/clip.webm': '/sdcard/my.folder/clip',
      'relative.avi': 'relative',
      '/a/.hidden': '/a/',
      '/a/b.c.d.e.mp4': '/a/b.c.d.e',
    };
    table.forEach((video, base) {
      test('$video -> base $base', () {
        final c = sidecarCandidates(video);
        expect(c.length, subtitleExtensions.length + 4 * 3);
        expect(c.first, '$base.srt');
        expect(
            c.sublist(0, 5), [for (final e in subtitleExtensions) '$base.$e']);
        expect(c, contains('$base.en.srt'));
        expect(c, contains('$base.hin.vtt'));
        expect(c.toSet().length, c.length);
        for (final x in c) {
          expect(x.startsWith('$base.'), isTrue);
        }
      });
    });
    final r = Random(77);
    for (var i = 0; i < 25; i++) {
      final dir = '/storage/${randomWord(r).replaceAll(' ', '_')}';
      final name = randomWord(r).replaceAll('.', '');
      final ext = ['mp4', 'mkv', 'avi', 'mov', 'webm'][r.nextInt(5)];
      final path = '$dir/$name.$ext';
      test('random video $path never keeps the video extension', () {
        final c = sidecarCandidates(path);
        for (final x in c) {
          expect(x.contains('.$ext'), isFalse);
          final sub = x.split('.').last;
          expect(subtitleExtensions, contains(sub));
        }
        expect(c.indexOf('$dir/$name.srt'), 0);
        expect(c.indexOf('$dir/$name.en.srt'),
            lessThan(c.indexOf('$dir/$name.hi.srt')));
      });
    }
    test('findSidecarSubtitle skips urls and null', () async {
      expect(await findSidecarSubtitle(null), isNull);
      expect(await findSidecarSubtitle('https://x.com/a.mp4'), isNull);
    });
    test('findSidecarSubtitle finds a real file next to the video', () async {
      final dir = await Directory.systemTemp.createTemp('subs');
      addTearDown(() => dir.delete(recursive: true));
      expect(await findSidecarSubtitle('${dir.path}/movie.mkv'), isNull);
      await File('${dir.path}/movie.en.srt').writeAsString('1\n');
      expect(await findSidecarSubtitle('${dir.path}/movie.mkv'),
          '${dir.path}/movie.en.srt');
      await File('${dir.path}/movie.vtt').writeAsString('WEBVTT\n');
      expect(await findSidecarSubtitle('${dir.path}/movie.mkv'),
          '${dir.path}/movie.vtt');
      await File('${dir.path}/movie.srt').writeAsString('1\n');
      expect(await findSidecarSubtitle('${dir.path}/movie.mkv'),
          '${dir.path}/movie.srt');
    });
  });

  group('PlayItem.fromUrl', () {
    const table = {
      'https://x.com/media/My%20Clip.mp4': 'My Clip.mp4',
      'https://x.com/': 'x.com',
      'https://x.com': 'x.com',
      'https://x.com/a/b/': 'x.com',
      'http://10.0.0.2:8080/live/stream.m3u8': 'stream.m3u8',
      'https://cdn.site.tv/v/clip.mp4?token=abc&e=1': 'clip.mp4',
      'https://cdn.site.tv/v/clip.mp4#t=30': 'clip.mp4',
      'https://x.com/%E0%A4%AB%E0%A4%BF%E0%A4%B2%E0%A5%8D%E0%A4%AE.mkv':
          'फिल्म.mkv',
      'https://x.com/50%25%20off.mp4': '50% off.mp4',
      'https://x.com/a%2520b.mp4': 'a%20b.mp4',
      'https://x.com/100%.mp4': '100%.mp4',
      'http://[bad': 'http://[bad',
    };
    table.forEach((url, title) {
      test('$url -> "$title"', () {
        final p = PlayItem.fromUrl(url);
        expect(p.title, title);
        expect(p.uri, url);
        expect(p.key, url);
        expect(p.isPrivate, isFalse);
        expect(p.assetId, isNull);
        expect(p.path, isNull);
        expect(p.isNetwork, url.startsWith('http'));
      });
    });
    final r = Random(9);
    for (var i = 0; i < 30; i++) {
      final name = '${randomWord(r)}%#?&é.mp4';
      final url = Uri.https('media.example.org', '/files/$i/$name').toString();
      test('encoded name #$i round-trips to "$name"', () {
        expect(PlayItem.fromUrl(url).title, name);
      });
    }
  });

  group('PlayItem.fromExternal', () {
    const table = <String, (String, String?)>{
      'file:///sdcard/Download/show.mkv': (
        'show.mkv',
        '/sdcard/Download/show.mkv'
      ),
      'file:///sdcard/My%20Videos/a%20b.mp4': (
        'a b.mp4',
        '/sdcard/My Videos/a b.mp4'
      ),
      'file:///sdcard/100%25.mp4': ('100%.mp4', '/sdcard/100%.mp4'),
      'content://media/external/video/media/42': ('42', null),
      'content://com.android.providers.downloads.documents/document/raw%3A%2Fstorage%2Femulated%2F0%2FDownload%2Fa.mp4':
          ('a.mp4', null),
      'content://com.whatsapp.provider.media/item/abc': ('abc', null),
      'content://authority': ('Video', null),
    };
    table.forEach((uri, expected) {
      test('$uri -> ${expected.$1}', () {
        final p = PlayItem.fromExternal(uri);
        expect(p.title, expected.$1);
        expect(p.path, expected.$2);
        expect(p.uri, uri);
        expect(p.key, uri);
        expect(p.isNetwork, isFalse);
      });
    });
  });

  group('PlayItem from library, recents and vault', () {
    for (final id in ['1', '42', '999999', '1234567890']) {
      test('fromEntry id $id', () {
        final v = makeVideo(id, title: 'v$id.mp4');
        final p = PlayItem.fromEntry(v);
        expect(p.uri, 'content://media/external/video/media/$id');
        expect(p.key, id);
        expect(p.assetId, id);
        expect(p.title, 'v$id.mp4');
        expect(p.path, '/storage/emulated/0/Movies/Trip/v$id.mp4');
        expect(p.isPrivate, isFalse);
      });
    }
    test('fromRecent finds the library path when the asset is known', () {
      final saved = VideoLibrary.instance.folders;
      addTearDown(() => VideoLibrary.instance.folders = saved);
      VideoLibrary.instance.folders = [
        VideoFolder('f', 'F', [makeVideo('7', title: 'seven.mp4')]),
      ];
      final p = PlayItem.fromRecent(RecentItem(
          key: '7',
          title: 'seven.mp4',
          uri: 'content://media/external/video/media/7',
          assetId: '7'));
      expect(p.path, '/storage/emulated/0/Movies/Trip/seven.mp4');
      expect(p.key, '7');
      final q = PlayItem.fromRecent(RecentItem(
          key: 'https://a/b.mp4', title: 'b.mp4', uri: 'https://a/b.mp4'));
      expect(q.path, isNull);
      expect(q.isNetwork, isTrue);
    });
    for (final name in ['a.mp4', 'Trip (1).mkv', 'é.webm']) {
      test('fromPrivate $name is private and keyed by title', () {
        final pv = PrivateVideo(File('/data/private/$name'), name, 'Movies/');
        final p = PlayItem.fromPrivate(pv);
        expect(p.isPrivate, isTrue);
        expect(p.key, 'private:$name');
        expect(p.uri, '/data/private/$name');
        expect(p.path, '/data/private/$name');
        expect(p.title, name);
        expect(pv.size, 0, reason: 'missing file has size 0');
      });
    }
  });
}
