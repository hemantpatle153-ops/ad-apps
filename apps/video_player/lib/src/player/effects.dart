import 'package:media_kit/media_kit.dart';

import '../settings.dart';

/// Equalizer presets in dB for the ten [eqBands].
const eqPresets = <String, List<double>>{
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass boost': [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
  'Movie': [3, 2, 1, 0, -1, 1, 3, 4, 3, 2],
  'Vocal': [-2, -2, -1, 1, 3, 4, 4, 3, 1, 0],
  'Rock': [5, 4, 2, -1, -2, -1, 2, 3, 4, 4],
  'Pop': [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2],
  'Jazz': [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
  'Classical': [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
  'Treble boost': [0, 0, 0, 0, 0, 1, 3, 5, 6, 7],
};

/// mpv audio filter chain for the equalizer and night mode, or '' for none.
String audioFilter(List<double> gains, {required bool night}) {
  final parts = <String>[
    for (var i = 0; i < eqBands.length && i < gains.length; i++)
      if (gains[i].abs() >= 0.1)
        'equalizer=f=${eqBands[i]}:width_type=o:width=1:g=${gains[i].toStringAsFixed(1)}',
    // Evens out loud explosions and quiet dialogue.
    if (night) 'dynaudnorm=f=250:g=15',
  ];
  return parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]';
}

/// Picture settings applied by mpv.
class VideoAdjust {
  int brightness = 0, contrast = 0, saturation = 0, gamma = 0, hue = 0;
  int rotate = 0;
  bool mirror = false;

  bool get isDefault =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      gamma == 0 &&
      hue == 0 &&
      rotate == 0 &&
      !mirror;
}

/// Player features that need libmpv properties (equalizer, delays, boost,
/// picture adjustments, A-B loop, decoder). All calls fail quietly, so a
/// libmpv build without a filter just leaves that feature off.
class PlayerEffects {
  PlayerEffects(this.player);

  final Player player;
  final adjust = VideoAdjust();
  double audioDelay = 0, subtitleDelay = 0;

  /// Caption clock speed; not 1 only after auto sync found captions made
  /// for another frame rate.
  double subtitleSpeed = 1;
  Duration? loopA, loopB;
  bool loopOne = false;

  bool get isNative => _mpv != null;

  NativePlayer? get _mpv =>
      player.platform is NativePlayer ? player.platform as NativePlayer : null;

  Future<void> set(String property, String value) async {
    try {
      await _mpv?.setProperty(property, value);
    } catch (_) {}
  }

  Future<String?> get(String property) async {
    try {
      return await _mpv?.getProperty(property);
    } catch (_) {
      return null;
    }
  }

  Future<void> command(List<String> args) async {
    try {
      await _mpv?.command(args);
    } catch (_) {}
  }

  /// Settings that apply to every video.
  Future<void> applyGlobal(Settings s) async {
    // Lets the volume go up to 200% for quiet videos.
    await set('volume-max', '200');
    // Keep 30 s ahead and the last ~50 MB behind in memory, so +-10 s jumps
    // usually land on video that is already loaded, even on links.
    await set('cache', 'yes');
    await set('demuxer-readahead-secs', '30');
    await set('demuxer-max-back-bytes', '${50 * 1024 * 1024}');
    await applyAudio(s);
  }

  Future<void> setHardwareDecoding(bool on) => set('hwdec', on ? 'auto-safe' : 'no');

  Future<void> applyAudio(Settings s) =>
      set('af', audioFilter(s.eqGains, night: s.nightMode));

  Future<void> setAudioDelay(double seconds) async {
    audioDelay = seconds;
    await set('audio-delay', seconds.toStringAsFixed(2));
  }

  Future<void> setSubtitleDelay(double seconds) async {
    subtitleDelay = seconds;
    await set('sub-delay', seconds.toStringAsFixed(2));
  }

  /// Moves captions by [delaySeconds] and runs their clock at [speed].
  Future<void> setSubtitleSync(double delaySeconds, double speed) async {
    subtitleDelay = delaySeconds;
    subtitleSpeed = speed;
    await set('sub-delay', delaySeconds.toStringAsFixed(3));
    await set('sub-speed', speed.toStringAsFixed(6));
  }

  /// Quick jump by [by] to the nearest keyframe: much faster than an exact
  /// seek, which has to decode every frame up to the target.
  Future<void> seekQuick(Duration by) =>
      command(['seek', (by.inMilliseconds / 1000).toStringAsFixed(3), 'relative+keyframes']);

  /// Shifts the captions so the next ([lines] = 1) or previous (-1) line
  /// shows now: tap it the moment you hear that line spoken.
  Future<void> subStep(int lines) async {
    await command(['sub-step', '$lines']);
    final v = double.tryParse(await get('sub-delay') ?? '');
    if (v != null) subtitleDelay = v;
  }

  Future<void> applyPicture() async {
    final a = adjust;
    await set('brightness', '${a.brightness}');
    await set('contrast', '${a.contrast}');
    await set('saturation', '${a.saturation}');
    await set('gamma', '${a.gamma}');
    await set('hue', '${a.hue}');
    await set('video-rotate', '${a.rotate}');
    await set('vf', a.mirror ? 'lavfi=[hflip]' : '');
  }

  Future<void> setLoopOne(bool on) async {
    loopOne = on;
    await set('loop-file', on ? 'inf' : 'no');
  }

  Future<void> setAbLoop(Duration? a, Duration? b) async {
    loopA = a;
    loopB = b;
    String secs(Duration? d) =>
        d == null ? 'no' : (d.inMilliseconds / 1000).toStringAsFixed(3);
    await set('ab-loop-a', secs(a));
    await set('ab-loop-b', secs(b));
  }

  Future<void> frameStep({bool back = false}) =>
      command([back ? 'frame-back-step' : 'frame-step']);

  /// Chapters in the file (mkv and some mp4), as (title, start).
  Future<List<(String, Duration)>> chapters() async {
    final n = int.tryParse(await get('chapter-list/count') ?? '') ?? 0;
    final out = <(String, Duration)>[];
    for (var i = 0; i < n && i < 200; i++) {
      final t = double.tryParse(await get('chapter-list/$i/time') ?? '');
      if (t == null) continue;
      final title = await get('chapter-list/$i/title');
      out.add((
        (title == null || title.isEmpty) ? 'Chapter ${i + 1}' : title,
        Duration(milliseconds: (t * 1000).round()),
      ));
    }
    return out;
  }
}
