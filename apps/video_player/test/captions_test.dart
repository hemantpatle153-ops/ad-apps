import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/captions/opensubtitles.dart';
import 'package:video_player_app/src/settings.dart';

void main() {
  group('movie hash', () {
    test('matches an independent implementation', () {
      final head = Uint8List.fromList([for (var i = 0; i < 65536; i++) (i * 7 + 3) % 256]);
      final tail = Uint8List.fromList([for (var i = 0; i < 65536; i++) (i * 13 + 255) % 256]);
      expect(movieHashOf(12909756, head, tail), '5fe05fdf60a53cbc');
    });

    test('wraps around 64 bits', () {
      final ones = Uint8List(65536)..fillRange(0, 65536, 255);
      expect(movieHashOf(70000, ones, ones), '000000000000d170');
    });
  });

  group('caption query from a file name', () {
    test('movie with year and release tags', () {
      final q = CaptionQuery.fromFileName('The.Dark.Knight.2008.1080p.BluRay.x264-YTS.mkv');
      expect(q.title, 'The Dark Knight');
      expect(q.year, 2008);
      expect(q.season, isNull);
    });

    test('show episode', () {
      final q = CaptionQuery.fromFileName('Mirzapur_S02E05_720p_WEB-DL.mp4');
      expect(q.title, 'Mirzapur');
      expect(q.season, 2);
      expect(q.episode, 5);
    });

    test('1x05 style and plain names', () {
      expect(CaptionQuery.fromFileName('Friends 1x05.avi').episode, 5);
      expect(CaptionQuery.fromFileName('holiday video.mp4').title, 'holiday video');
      expect(CaptionQuery.fromFileName('2012.mkv').title, '2012');
    });
  });

  test('results put exact file matches first, then popular ones', () {
    Map<String, Object?> item(int id, int downloads, bool exact) => {
          'attributes': {
            'language': 'en',
            'release': 'r$id',
            'download_count': downloads,
            'moviehash_match': exact,
            'files': [
              {'file_id': id, 'file_name': 'f$id.srt'}
            ],
          }
        };
    final r = CaptionResult.listFromJson({
      'data': [item(1, 900, false), item(2, 5, true), item(3, 2000, false), {'bad': 1}],
    });
    expect([for (final x in r) x.fileId], [2, 3, 1]);
    expect(r.first.exactMatch, isTrue);
  });

  test('search without an API key explains instead of calling out', () async {
    final api = OpenSubtitles(apiKey: '');
    expect(api.available, isFalse);
    expect(
        () => api.search(query: const CaptionQuery(title: 'x'), languages: ['en']),
        throwsA(isA<CaptionException>()));
  });

  test('downloaded captions and languages are remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.open();
    expect(s.captionLanguages, ['en']);
    s.setCaptionLanguages(['en', 'hi']);
    s.setCaption('video1', '/data/captions/1-en.srt');
    final again = await Settings.open();
    expect(again.captionLanguages, ['en', 'hi']);
    expect(again.captionFor('video1'), '/data/captions/1-en.srt');
    again.setCaption('video1', null);
    expect((await Settings.open()).captionFor('video1'), isNull);
  });

  test("a person's own key is used and remembered", () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.open();
    expect(s.openSubtitlesKey, '');
    expect(captionApiKey(''), openSubtitlesApiKey);
    s.setOpenSubtitlesKey('  abc123  ');
    expect((await Settings.open()).openSubtitlesKey, 'abc123');
    expect(captionApiKey(' abc123 '), 'abc123');
    expect(OpenSubtitles(apiKey: captionApiKey('abc123')).available, isTrue);
  });
}
