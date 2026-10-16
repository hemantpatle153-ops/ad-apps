import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/party/drive.dart';
import 'package:video_player_app/src/party/online.dart';

void main() {
  test('resume point comes from the Range header Drive returns', () {
    expect(DriveShare.nextByte(null), 0);
    expect(DriveShare.nextByte(''), 0);
    expect(DriveShare.nextByte('bytes=0-8388607'), 8388608);
  });

  test('stream link reads the file with the API key', () {
    expect(DriveShare.streamUrl('abc'),
        startsWith('https://www.googleapis.com/drive/v3/files/abc?alt=media&key='));
  });

  test('a Drive video travels as a link and keeps its file id', () {
    const v = OnlineVideo(title: 'Trip', url: 'https://x', durationMs: 5, driveId: 'abc');
    final back = OnlineVideo.fromJson(v.toJson());
    expect(back.isLink, isTrue);
    expect(back.isDrive, isTrue);
    expect(back.driveId, 'abc');
    expect(const OnlineVideo(title: 'Local').isDrive, isFalse);
  });
}
