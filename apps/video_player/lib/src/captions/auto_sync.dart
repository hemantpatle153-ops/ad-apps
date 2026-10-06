import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../library/subtitle_cues.dart';
import '../library/subtitle_sync.dart';
import '../player/effects.dart';
import '../player/system_channel.dart';

/// Path of the caption file showing now, or null for captions inside the
/// video (auto sync can only read files).
String? captionFileOf(Player player) {
  final t = player.state.track.subtitle;
  if (!t.uri) return null;
  final id = t.id;
  final path = id.startsWith('file://') ? Uri.parse(id).toFilePath() : id;
  if (path.startsWith('http') || path.startsWith('content://')) return null;
  return path;
}

/// Listens to parts of the video and moves the caption file showing now to
/// match the speech. Returns null when it worked, or a message saying why
/// it didn't.
Future<String?> autoSyncCaptions({
  required Player player,
  required PlayerEffects fx,
  required String videoUri,
}) async {
  final path = captionFileOf(player);
  if (path == null || !File(path).existsSync()) {
    return 'Auto sync works on caption files (downloaded or loaded). '
        'Use the buttons below for captions inside the video.';
  }
  if (videoUri.startsWith('http')) {
    return 'Auto sync works on videos stored on the phone.';
  }
  final duration = player.state.duration.inMilliseconds;
  if (duration <= 0) return 'Wait until the video has started.';
  try {
    final cues = await readCues(path);
    if (cues.length < 10) return 'This caption file has too few lines to sync.';
    final windows = <AudioWindow>[];
    for (final (start, length) in syncWindows(duration)) {
      windows.add(AudioWindow(
        start,
        await SystemChannel.instance
            .speechEnergy(videoUri, startMs: start, durationMs: length),
      ));
    }
    final result = await Isolate.run(() => findSync(cues, windows));
    if (result == null || result.confidence < minSyncConfidence) {
      return "Couldn't find a sure match. Use the buttons below.";
    }
    await fx.setSubtitleSync(result.delayMs / 1000, result.speed);
    return null;
  } catch (e) {
    debugPrint('auto sync failed: $e');
    return "Couldn't read this video's sound. Use the buttons below.";
  }
}
