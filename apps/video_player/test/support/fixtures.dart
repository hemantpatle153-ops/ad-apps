import 'dart:math';

import 'package:photo_manager/photo_manager.dart';
import 'package:video_player_app/src/library/video_library.dart';

/// Builds a [VideoEntry] backed by an in-memory [AssetEntity] (no plugin).
VideoEntry makeVideo(
  String id, {
  String? title = 'clip.mp4',
  String folder = 'Trip',
  int seconds = 60,
  int size = 0,
  int modified = 0,
  int created = 0,
  int width = 1920,
  int height = 1080,
  int orientation = 0,
  String? relativePath = 'Movies/Trip/',
}) {
  final v = VideoEntry(
    AssetEntity(
      id: id,
      typeInt: AssetType.video.index,
      width: width,
      height: height,
      duration: seconds,
      orientation: orientation,
      title: title,
      createDateSecond: created,
      modifiedDateSecond: modified,
      relativePath: relativePath,
    ),
    folder,
  );
  v.size = size;
  return v;
}

/// Deterministic list of distinct integers from a seeded generator.
List<int> distinctInts(int seed, int count, int max, {int min = 0}) {
  final r = Random(seed);
  final out = <int>{};
  while (out.length < count) {
    out.add(min + r.nextInt(max - min));
  }
  return out.toList();
}

const _letters =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-';

/// Random word made of letters, digits, space, underscore and dash.
String randomWord(Random r, {int minLen = 1, int maxLen = 12}) {
  final len = minLen + r.nextInt(maxLen - minLen + 1);
  return String.fromCharCodes(List.generate(
      len, (_) => _letters.codeUnitAt(r.nextInt(_letters.length))));
}
