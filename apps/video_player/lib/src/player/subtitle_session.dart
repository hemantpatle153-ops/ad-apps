import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../library/subtitle_cues.dart';
import '../library/subtitle_sync.dart';
import 'play_item.dart';
import 'system_channel.dart';

/// The subtitle file loaded for the current video and its timing fix.
/// Reset whenever another video starts.
class SubtitleSession extends ChangeNotifier {
  SubtitleSession(this.player);

  final Player player;

  /// Path of a subtitle file the app loaded (picked or found next to the
  /// video); null for tracks inside the video.
  String? file;

  /// Subtitles show this much later (negative: earlier).
  int delayMs = 0;

  /// Subtitle clock speed, for files made for another frame rate.
  double speed = 1;

  bool syncing = false;

  Future<void> load(String path, String title) async {
    file = path;
    await player.setSubtitleTrack(SubtitleTrack.uri(path, title: title));
    await _apply(delay: 0, newSpeed: 1);
  }

  void useEmbedded() {
    file = null;
    notifyListeners();
  }

  Future<void> reset() => _apply(delay: 0, newSpeed: 1);

  Future<void> nudge(int ms) => _apply(delay: delayMs + ms, newSpeed: speed);

  Future<void> _apply({required int delay, required double newSpeed}) async {
    delayMs = delay;
    speed = newSpeed;
    notifyListeners();
    final p = player.platform;
    if (p is NativePlayer) {
      await p.setProperty('sub-delay', (delay / 1000).toStringAsFixed(3));
      await p.setProperty('sub-speed', newSpeed.toStringAsFixed(6));
    }
  }

  /// Listens to parts of the video and moves the loaded subtitle file to
  /// match the speech. Returns null when it worked, or a message saying why
  /// it didn't.
  Future<String?> autoSync(PlayItem item) async {
    final path = file;
    if (path == null) {
      return 'Auto sync works on subtitle files loaded from the phone. '
          'Use the manual buttons for subtitles inside the video.';
    }
    if (item.isNetwork) return 'Auto sync works on videos stored on the phone.';
    final duration = player.state.duration.inMilliseconds;
    if (duration <= 0) return 'Wait until the video has started.';
    syncing = true;
    notifyListeners();
    try {
      final cues = await readCues(path);
      if (cues.length < 10) return 'This subtitle file has too few lines to sync.';
      final windows = <AudioWindow>[];
      for (final (start, length) in syncWindows(duration)) {
        windows.add(AudioWindow(
          start,
          await SystemChannel.instance
              .speechEnergy(item.uri, startMs: start, durationMs: length),
        ));
      }
      final result = await Isolate.run(() => findSync(cues, windows));
      if (result == null || result.confidence < minSyncConfidence) {
        return "Couldn't find a sure match. Use the manual buttons.";
      }
      await _apply(delay: result.delayMs, newSpeed: result.speed);
      return null;
    } catch (e) {
      debugPrint('auto sync failed: $e');
      return "Couldn't read this video's sound. Use the manual buttons.";
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}

/// "+1.5 s", "-0.3 s", "0.0 s".
String formatDelay(int ms) {
  final s = (ms / 1000).toStringAsFixed(1);
  return ms > 0 ? '+$s s' : '$s s';
}
