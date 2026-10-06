import 'dart:math' as math;
import 'dart:typed_data';

import 'subtitle_cues.dart';

/// Loudness of a stretch of the video's sound, one value per [frameMs].
class AudioWindow {
  const AudioWindow(this.startMs, this.energy);

  /// Video time of the first frame.
  final int startMs;

  /// Loudness in dB per frame (speech band); -1000 where nothing was decoded.
  final Float32List energy;
}

/// How to show subtitle time s at video time v = s * speed + delayMs.
/// Matches mpv's sub-speed and sub-delay.
class SyncResult {
  const SyncResult(this.speed, this.delayMs, this.confidence);
  final double speed;
  final int delayMs;

  /// How far the best match stands out from the others (z-score).
  final double confidence;

  @override
  String toString() => 'SyncResult(speed $speed, delay $delayMs ms, z $confidence)';
}

/// Common frame-rate mix-ups (23.976 / 24 / 25 fps) plus none.
const syncSpeeds = [1.0, 25 / 23.976, 23.976 / 25, 25 / 24, 24 / 25, 24 / 23.976, 23.976 / 24];

/// Below this a match is treated as a guess and not applied.
const minSyncConfidence = 5.0;

/// Finds the speed and delay that best line subtitle [cues] up with speech in
/// [windows]: inside a cue the sound should be louder than outside it.
///
/// Tries every delay within [maxShiftMs] in steps of [frameMs] for each
/// speed in [syncSpeeds]. Returns null when there is nothing to compare.
SyncResult? findSync(
  List<Cue> cues,
  List<AudioWindow> windows, {
  int frameMs = 100,
  int maxShiftMs = 120000,
}) {
  if (cues.isEmpty || windows.isEmpty) return null;
  final shifts = maxShiftMs ~/ frameMs;
  final nShifts = 2 * shifts + 1;
  SyncResult? best;
  double bestPeak = double.negativeInfinity;

  // Loudness relative to each window's own level, so loud and quiet
  // scenes count the same.
  final norm = [for (final w in windows) _standardise(w.energy)];

  for (final speed in syncSpeeds) {
    final total = Float64List(nShifts);
    for (var wi = 0; wi < windows.length; wi++) {
      final w = windows[wi];
      final z = norm[wi];
      if (z == null) continue;
      final n = z.length;
      // Cue cover in video time with delay 0, from (start - max shift) to
      // (end + max shift), one slot per frame.
      final from = w.startMs - maxShiftMs;
      final mask = Uint8List(n + 2 * shifts);
      for (final c in cues) {
        final a = ((c.startMs * speed - from) / frameMs).floor();
        final b = ((c.endMs * speed - from) / frameMs).ceil();
        if (b < 0 || a >= mask.length) continue;
        for (var k = math.max(a, 0); k < math.min(b, mask.length); k++) {
          mask[k] = 1;
        }
      }
      // With delay d (in frames), video frame f shows subtitle cover at
      // mask[f + shifts - d].
      for (var s = 0; s < nShifts; s++) {
        final off = 2 * shifts - s; // == shifts - d where d = s - shifts
        var sum = 0.0;
        for (var f = 0; f < n; f++) {
          if (mask[f + off] != 0) sum += z[f];
        }
        total[s] += sum;
      }
    }
    final peak = _peak(total);
    if (peak == null) continue;
    if (peak.z > bestPeak) {
      bestPeak = peak.z;
      best = SyncResult(speed, (peak.index - shifts) * frameMs, peak.z);
    }
  }
  return best;
}

/// (x - mean) / sd over frames with sound; silent padding scores 0.
Float64List? _standardise(Float32List e) {
  final valid = [for (final v in e) if (v > -999) v];
  if (valid.length < 10) return null;
  final mean = valid.reduce((a, b) => a + b) / valid.length;
  var varSum = 0.0;
  for (final v in valid) {
    varSum += (v - mean) * (v - mean);
  }
  final sd = math.sqrt(varSum / valid.length);
  if (sd < 1e-6) return null;
  return Float64List.fromList(
      [for (final v in e) v > -999 ? (v - mean) / sd : 0.0]);
}

class _Peak {
  const _Peak(this.index, this.z);
  final int index;
  final double z;
}

_Peak? _peak(Float64List xs) {
  if (xs.length < 3) return null;
  var bi = 0;
  var sum = 0.0;
  for (var i = 0; i < xs.length; i++) {
    sum += xs[i];
    if (xs[i] > xs[bi]) bi = i;
  }
  final mean = sum / xs.length;
  var varSum = 0.0;
  for (final x in xs) {
    varSum += (x - mean) * (x - mean);
  }
  final sd = math.sqrt(varSum / xs.length);
  if (sd < 1e-9) return null;
  return _Peak(bi, (xs[bi] - mean) / sd);
}

/// Where to listen: up to [count] stretches of [lengthMs] spread over the
/// video, skipping the first and last 5% (titles and credits).
List<(int, int)> syncWindows(int durationMs,
    {int count = 3, int lengthMs = 240000}) {
  if (durationMs <= 0) return const [];
  if (durationMs <= lengthMs * count) {
    return [(0, durationMs)];
  }
  final first = durationMs * 0.05;
  final last = durationMs * 0.95 - lengthMs;
  return [
    for (var i = 0; i < count; i++)
      ((first + (last - first) * i / (count - 1)).round(), lengthMs),
  ];
}
