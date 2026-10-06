import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/settings.dart';

void main() {
  test('the subtitle file picked for a video is remembered', () async {
    SharedPreferences.setMockInitialValues({
      'capLangs': ['en'],
      'osToken': 't'
    });
    final s = await Settings.open();
    s.setCaption('video1', '/data/subs/movie.srt');
    final again = await Settings.open();
    expect(again.captionFor('video1'), '/data/subs/movie.srt');
    again.setCaption('video1', null);
    expect((await Settings.open()).captionFor('video1'), isNull);
    // Leftovers from the removed online search are cleared.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('capLangs'), isFalse);
    expect(prefs.containsKey('osToken'), isFalse);
  });
}
