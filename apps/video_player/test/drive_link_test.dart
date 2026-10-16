import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/player/drive_link.dart';
import 'package:video_player_app/src/player/play_item.dart';

void main() {
  const id = '1AbC-dEf_GhIjKlMnOpQrStUvWxYz0123';
  const stream =
      'https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t';

  test('Drive share links give the file id', () {
    for (final link in [
      'https://drive.google.com/file/d/$id/view?usp=sharing',
      'https://drive.google.com/file/d/$id/view?usp=drive_link',
      'https://drive.google.com/file/u/0/d/$id/preview',
      'https://drive.google.com/open?id=$id',
      'https://drive.google.com/uc?id=$id&export=download',
      ' https://drive.usercontent.google.com/download?id=$id ',
    ]) {
      expect(driveFileId(link), id, reason: link);
    }
  });

  test('other links are left alone', () {
    for (final link in [
      'https://example.com/file/d/$id/view',
      'https://drive.google.com/drive/folders/$id',
      'https://drive.google.com/file/d/short/view',
      'not a link',
    ]) {
      expect(driveFileId(link), isNull, reason: link);
    }
    expect(streamUrlFor('https://example.com/a.mp4'), 'https://example.com/a.mp4');
  });

  test('a Drive link plays through its stream address', () {
    final item = PlayItem.fromUrl('https://drive.google.com/file/d/$id/view');
    expect(item.uri, stream);
    expect(item.key, stream);
    expect(item.title, 'Google Drive video');
    expect(item.isNetwork, isTrue);
    expect(PlayItem.fromUrl('https://drive.google.com/open?id=$id', title: 'Movie').title,
        'Movie');
    expect(PlayItem.fromUrl('https://example.com/v/clip.mp4').title, 'clip.mp4');
  });

  test('file name from the Drive page title', () {
    expect(driveTitleFromHtml('<html><title>Holiday &amp; Co.mp4 - Google Drive</title>'),
        'Holiday & Co.mp4');
    expect(driveTitleFromHtml('<title>Google Drive: Sign-in</title>'), isNull);
    expect(driveTitleFromHtml('no title'), isNull);
  });
}
