import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../format.dart';
import '../library/subtitles.dart';
import '../settings.dart';
import 'background_audio.dart';
import 'play_item.dart';
import 'player_overlays.dart';
import 'player_sheets.dart';
import 'system_channel.dart';

enum FitMode {
  fit('Fit', BoxFit.contain, null, Icons.fit_screen_rounded),
  stretch('Stretch', BoxFit.fill, null, Icons.open_in_full_rounded),
  crop('Crop', BoxFit.cover, null, Icons.crop_rounded),
  wide('16:9', BoxFit.contain, 16 / 9, Icons.crop_16_9_rounded),
  classic('4:3', BoxFit.contain, 4 / 3, Icons.crop_7_5_rounded);

  const FitMode(this.label, this.boxFit, this.ratio, this.icon);
  final String label;
  final BoxFit boxFit;
  final double? ratio;
  final IconData icon;
}

enum Rotation {
  landscape('Landscape', Icons.stay_current_landscape_rounded),
  portrait('Portrait', Icons.stay_current_portrait_rounded),
  auto('Auto-rotate', Icons.screen_rotation_rounded);

  const Rotation(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _Drag { none, seek, brightness, volume, zoom }

/// Opens the player full screen. Shows an interstitial (with cooldown)
/// only after the player closes, never during playback.
Future<void> openPlayer(
  BuildContext context,
  Settings settings,
  List<PlayItem> queue, {
  int index = 0,
}) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => PlayerScreen(settings: settings, queue: queue, index: index),
  ));
  await AdService.instance.maybeShowInterstitial();
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.settings,
    required this.queue,
    this.index = 0,
  });

  final Settings settings;
  final List<PlayItem> queue;
  final int index;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final Player player = Player(
    configuration: const PlayerConfiguration(title: 'Video Player'),
  );
  late final VideoController controller = VideoController(player);
  late int index = widget.index;
  Settings get settings => widget.settings;
  PlayItem get item => widget.queue[index];

  final _subs = <StreamSubscription>[];
  Timer? _hideTimer, _indicatorTimer, _saveTimer, _resumeTimer, _rippleTimer;

  bool _controlsVisible = true;
  bool _locked = false;
  bool _lockHintVisible = false;
  bool _showRemaining = false;
  bool _backgroundSession = false;
  bool _pipSupported = false;
  FitMode _fit = FitMode.fit;
  Rotation? _rotation;
  double _zoom = 1;

  // Gesture state.
  _Drag _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  Duration _seekFrom = Duration.zero, _seekTo = Duration.zero;
  double _levelFrom = 0, _zoomFrom = 1;
  double _brightness = 0.5, _volume = 0.5;
  Offset? _doubleTapAt;
  bool? _rippleForward;
  int _rippleSeconds = 0;

  Widget? _indicator;
  Duration? _resumedFrom;
  String? _error;

  // Scrubbing the seek bar.
  double? _scrub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChannel.instance.inPip.addListener(_onPip);
    _subs.addAll([
      player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      player.stream.error.listen((e) {
        if (mounted && player.state.duration == Duration.zero) {
          setState(() => _error = 'Can\'t play this video');
        }
      }),
      player.stream.playing.listen((playing) {
        _updateAutoPip();
        if (playing) _scheduleHide();
      }),
      player.stream.width.listen((_) => _videoSizeChanged()),
      player.stream.height.listen((_) => _videoSizeChanged()),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
    _initDevice();
    _open(index);
  }

  Future<void> _initDevice() async {
    _pipSupported = await SystemChannel.instance.pipSupported();
    try {
      await FlutterVolumeController.updateShowSystemUI(false);
      _volume = await FlutterVolumeController.getVolume() ?? 0.5;
    } catch (_) {}
    try {
      _brightness = await ScreenBrightness.instance.application;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _open(int i) async {
    _saveProgress();
    setState(() {
      index = i;
      _error = null;
      _resumedFrom = null;
      _zoom = 1;
    });
    final it = item;
    final saved = settings.resume ? settings.positionFor(it.key) : null;
    final start = saved != null && saved > Duration.zero ? saved : null;
    await player.open(Media(it.uri, start: start));
    if (settings.rememberSpeed && settings.lastSpeed != 1) {
      await player.setRate(settings.lastSpeed);
    }
    if (start != null && mounted) {
      setState(() => _resumedFrom = start);
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _resumedFrom = null);
      });
    }
    if (!it.isPrivate) {
      settings.addRecent(RecentItem(
      key: it.key,
      title: it.title,
      uri: it.uri,
      assetId: it.assetId,
      position: start ?? Duration.zero,
      ));
    }
    if (settings.leaveAction == LeaveAction.audio || _backgroundSession) {
      unawaited(BackgroundAudio.instance.attach(player, it.title));
    }
    unawaited(_loadSidecar(it));
    _scheduleHide();
  }

  /// Loads "movie.srt" next to "movie.mp4" once the file has opened.
  Future<void> _loadSidecar(PlayItem it) async {
    final srt = await findSidecarSubtitle(it.path);
    if (srt == null) return;
    try {
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return;
    }
    if (!mounted || item != it) return;
    await player.setSubtitleTrack(
        SubtitleTrack.uri(srt, title: srt.split('/').last));
  }

  void _saveProgress() {
    final d = player.state.duration;
    if (d <= Duration.zero || widget.queue.isEmpty) return;
    settings.savePosition(item.key, player.state.position, d);
  }

  void _onCompleted() {
    _saveProgress();
    if (index < widget.queue.length - 1) {
      _open(index + 1);
    } else {
      _showControls(stay: true);
    }
  }

  // Orientation ------------------------------------------------------------

  void _videoSizeChanged() {
    final w = player.state.width, h = player.state.height;
    if (w == null || h == null || w == 0 || h == 0) return;
    if (_rotation == null) {
      _applyRotation(w >= h ? Rotation.landscape : Rotation.portrait);
    }
    _updateAutoPip();
  }

  void _applyRotation(Rotation r) {
    _rotation = r;
    SystemChrome.setPreferredOrientations(switch (r) {
      Rotation.landscape => [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      Rotation.portrait => [DeviceOrientation.portraitUp],
      Rotation.auto => [],
    });
    if (mounted) setState(() {});
  }

  // Picture-in-picture and background ---------------------------------------

  void _onPip() => setState(() {
        if (SystemChannel.instance.inPip.value) _controlsVisible = false;
      });

  void _updateAutoPip() {
    final want = _pipSupported &&
        settings.leaveAction == LeaveAction.pip &&
        !_backgroundSession &&
        player.state.playing;
    SystemChannel.instance
        .setAutoPip(want, player.state.width, player.state.height);
  }

  Future<void> _enterPip() async {
    final ok = await SystemChannel.instance
        .enterPip(player.state.width, player.state.height);
    if (!ok) _flash(Icons.picture_in_picture_alt_rounded, 'Not supported on this phone');
  }

  Future<void> _playInBackground() async {
    if (!player.state.playing) await player.play();
    await BackgroundAudio.instance.attach(player, item.title);
    if (!BackgroundAudio.instance.available) {
      _flash(Icons.headphones_rounded, 'Background audio is not available');
      return;
    }
    setState(() => _backgroundSession = true);
    _updateAutoPip();
    await SystemChannel.instance.moveToBack();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _saveProgress();
      final keepPlaying = SystemChannel.instance.inPip.value ||
          _backgroundSession ||
          (settings.leaveAction == LeaveAction.audio &&
              BackgroundAudio.instance.available);
      if (!keepPlaying) player.pause();
    }
  }

  // Controls visibility ----------------------------------------------------

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && player.state.playing && _scrub == null) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls({bool stay = false}) {
    setState(() => _controlsVisible = true);
    if (!stay) _scheduleHide();
  }

  void _toggleControls() {
    if (_locked) {
      setState(() => _lockHintVisible = !_lockHintVisible);
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _lockHintVisible = false);
      });
      return;
    }
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _flash(IconData icon, String text, {String? subtext, double? level}) {
    _indicatorTimer?.cancel();
    setState(() => _indicator =
        GestureIndicator(icon: icon, text: text, subtext: subtext, level: level));
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _indicator = null);
    });
  }

  // Gestures ----------------------------------------------------------------

  void _onDoubleTap(Size size) {
    if (_locked) return;
    final x = _doubleTapAt?.dx ?? size.width / 2;
    if (x > size.width * 0.35 && x < size.width * 0.65) {
      player.playOrPause();
      _flash(player.state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          player.state.playing ? 'Pause' : 'Play');
      return;
    }
    final forward = x >= size.width / 2;
    _seekBy(Duration(seconds: forward ? 10 : -10));
    _rippleTimer?.cancel();
    setState(() {
      _rippleSeconds = _rippleForward == forward ? _rippleSeconds + 10 : 10;
      _rippleForward = forward;
    });
    _rippleTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _rippleForward = null);
    });
  }

  void _seekBy(Duration by) {
    final d = player.state.duration;
    var t = player.state.position + by;
    if (t < Duration.zero) t = Duration.zero;
    if (d > Duration.zero && t > d) t = d;
    player.seek(t);
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_locked) return;
    _drag = _Drag.none;
    _dragStart = d.localFocalPoint;
    _zoomFrom = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_locked) return;
    if (d.pointerCount >= 2) {
      _drag = _Drag.zoom;
      final z = (_zoomFrom * d.scale).clamp(1.0, 4.0);
      setState(() => _zoom = z);
      _flash(Icons.zoom_in_rounded, '${(z * 100).round()}%');
      return;
    }
    if (_drag == _Drag.zoom) return;
    final delta = d.localFocalPoint - _dragStart;
    if (_drag == _Drag.none) {
      if (delta.distance < 14) return;
      if (delta.dx.abs() > delta.dy.abs()) {
        if (player.state.duration <= Duration.zero) return;
        _drag = _Drag.seek;
        _seekFrom = player.state.position;
      } else if (_dragStart.dx < size.width / 2) {
        _drag = _Drag.brightness;
        _levelFrom = _brightness;
      } else {
        _drag = _Drag.volume;
        _levelFrom = _volume;
      }
    }
    switch (_drag) {
      case _Drag.seek:
        final total = player.state.duration;
        // A full swipe covers 2 minutes, or the whole video if shorter.
        final span = total < const Duration(minutes: 2)
            ? total
            : const Duration(minutes: 2);
        var t = _seekFrom + span * (delta.dx / size.width);
        if (t < Duration.zero) t = Duration.zero;
        if (t > total) t = total;
        _seekTo = t;
        final diff = t - _seekFrom;
        _flash(diff.isNegative ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
            '${diff.isNegative ? '' : '+'}${formatDuration(diff)}',
            subtext: '${formatDuration(t)} / ${formatDuration(total)}');
      case _Drag.brightness:
        final v = (_levelFrom - delta.dy / (size.height * 0.75)).clamp(0.0, 1.0);
        _brightness = v;
        ScreenBrightness.instance.setApplicationScreenBrightness(v).catchError((_) {});
        _flash(Icons.brightness_6_rounded, '${(v * 100).round()}%', level: v);
      case _Drag.volume:
        final v = (_levelFrom - delta.dy / (size.height * 0.75)).clamp(0.0, 1.0);
        _volume = v;
        FlutterVolumeController.setVolume(v).catchError((_) {});
        _flash(v == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            '${(v * 100).round()}%', level: v);
      case _Drag.none:
      case _Drag.zoom:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_drag == _Drag.seek) player.seek(_seekTo);
    _drag = _Drag.none;
  }

  // Lifecycle ---------------------------------------------------------------

  @override
  void dispose() {
    _saveProgress();
    final pos = player.state.position, dur = player.state.duration;
    if (widget.queue.isNotEmpty && !item.isPrivate) {
      final recent = RecentItem(
        key: item.key,
        title: item.title,
        uri: item.uri,
        assetId: item.assetId,
        position: pos,
        duration: dur,
      );
      // Not during dispose: the update rebuilds the screens underneath.
      scheduleMicrotask(() => settings.addRecent(recent));
    }
    WidgetsBinding.instance.removeObserver(this);
    SystemChannel.instance.inPip.removeListener(_onPip);
    SystemChannel.instance.setAutoPip(false, null, null);
    for (final s in _subs) {
      s.cancel();
    }
    for (final t in [_hideTimer, _indicatorTimer, _saveTimer, _resumeTimer, _rippleTimer]) {
      t?.cancel();
    }
    BackgroundAudio.instance.detach();
    player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    FlutterVolumeController.updateShowSystemUI(true).catchError((_) {});
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    super.dispose();
  }

  // UI ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final inPip = SystemChannel.instance.inPip.value;
    final video = Video(
      controller: controller,
      controls: NoVideoControls,
      fit: _fit.boxFit,
      aspectRatio: _fit.ratio,
      wakelock: true,
      pauseUponEnteringBackgroundMode: false,
      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
    );
    return PopScope(
      canPop: !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _locked) _toggleControls();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: inPip
              ? Stack(fit: StackFit.expand, children: [video, _subtitles(pip: true)])
              : LayoutBuilder(builder: (context, c) {
                  final size = c.biggest;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRect(child: Transform.scale(scale: _zoom, child: video)),
                      _subtitles(),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleControls,
                        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                        onDoubleTap: () => _onDoubleTap(size),
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: (d) => _onScaleUpdate(d, size),
                        onScaleEnd: _onScaleEnd,
                      ),
                      if (_rippleForward != null)
                        IgnorePointer(
                          child: DoubleTapRipple(
                              forward: _rippleForward!, seconds: _rippleSeconds),
                        ),
                      _buffering(),
                      if (_indicator != null)
                        IgnorePointer(child: Center(child: _indicator)),
                      if (_error != null) _errorView(),
                      if (_locked) _lockOverlay() else _controls(context),
                      if (_resumedFrom != null && !_locked) _resumePill(),
                    ],
                  );
                }),
        ),
      ),
    );
  }

  Widget _subtitles({bool pip = false}) {
    return IgnorePointer(
      child: StreamBuilder<List<String>>(
        stream: player.stream.subtitle,
        initialData: player.state.subtitle,
        builder: (context, snap) {
          return AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.fromLTRB(
                24, 0, 24, pip ? 6 : (_controlsVisible && !_locked ? 120 : 28)),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SubtitleText(
                lines: snap.data ?? const [],
                size: pip ? 11 : settings.subtitleSize,
                color: Color(settings.subtitleColor),
                background: settings.subtitleBackground,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buffering() => IgnorePointer(
        child: StreamBuilder<bool>(
          stream: player.stream.buffering,
          initialData: player.state.buffering,
          builder: (context, snap) => snap.data == true && _error == null
              ? const Center(
                  child: SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white)))
              : const SizedBox.shrink(),
        ),
      );

  Widget _errorView() => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: Colors.black87, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 40),
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 4),
            Text(item.title,
                style: const TextStyle(color: Colors.white60),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Close')),
          ]),
        ),
      );

  Widget _resumePill() => Positioned(
        left: 0,
        right: 0,
        top: 90,
        child: Center(
          child: Material(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Resumed from ${formatDuration(_resumedFrom!)}',
                    style: const TextStyle(color: Colors.white)),
                TextButton(
                  onPressed: () {
                    player.seek(Duration.zero);
                    setState(() => _resumedFrom = null);
                  },
                  child: const Text('Start over'),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _lockOverlay() => AnimatedOpacity(
        opacity: _lockHintVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_lockHintVisible,
          child: SafeArea(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  IconButton.filled(
                    iconSize: 30,
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black),
                    onPressed: () {
                      setState(() {
                        _locked = false;
                        _lockHintVisible = false;
                      });
                      _showControls();
                    },
                    icon: const Icon(Icons.lock_rounded),
                  ),
                  const SizedBox(height: 6),
                  const Text('Tap to unlock',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _controls(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Stack(children: [
          // Scrims so white icons read on bright video.
          const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 130,
              child: _Scrim(top: true)),
          const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 170,
              child: _Scrim(top: false)),
          SafeArea(
            child: Column(children: [
              _topBar(),
              Expanded(child: _centerButtons()),
              _seekBar(accent),
              _bottomRow(),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _icon(IconData icon, VoidCallback onTap, {String? tip, double size = 24}) =>
      IconButton(
        tooltip: tip,
        onPressed: () {
          onTap();
          _scheduleHide();
        },
        icon: Icon(icon, color: Colors.white, size: size),
      );

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(children: [
          _icon(Icons.arrow_back_rounded, () => Navigator.maybePop(context), tip: 'Back'),
          const SizedBox(width: 4),
          Expanded(
            child: Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          _icon(Icons.audiotrack_rounded, _openAudio, tip: 'Audio track'),
          _icon(Icons.subtitles_rounded, _openSubtitles, tip: 'Subtitles'),
          StreamBuilder<double>(
            stream: player.stream.rate,
            initialData: player.state.rate,
            builder: (context, snap) => TextButton(
              onPressed: _openSpeed,
              child: Text(formatSpeed(snap.data ?? 1),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          if (_pipSupported)
            _icon(Icons.picture_in_picture_alt_rounded, _enterPip,
                tip: 'Picture-in-picture'),
          _icon(Icons.more_vert_rounded, _openMore, tip: 'More'),
        ]),
      );

  Widget _centerButtons() => StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          final ended = player.state.completed;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.queue.length > 1)
                _icon(Icons.skip_previous_rounded,
                    index > 0 ? () => _open(index - 1) : () => player.seek(Duration.zero),
                    size: 36, tip: 'Previous'),
              const SizedBox(width: 12),
              _icon(Icons.replay_10_rounded, () => _seekBy(const Duration(seconds: -10)),
                  size: 36, tip: 'Back 10 seconds'),
              const SizedBox(width: 18),
              Material(
                color: Colors.white.withValues(alpha: 0.18),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    if (ended) {
                      player.seek(Duration.zero);
                      player.play();
                    } else {
                      player.playOrPause();
                    }
                    _scheduleHide();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      ended
                          ? Icons.replay_rounded
                          : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              _icon(Icons.forward_10_rounded, () => _seekBy(const Duration(seconds: 10)),
                  size: 36, tip: 'Forward 10 seconds'),
              const SizedBox(width: 12),
              if (widget.queue.length > 1)
                _icon(Icons.skip_next_rounded,
                    index < widget.queue.length - 1 ? () => _open(index + 1) : () {},
                    size: 36, tip: 'Next'),
            ],
          );
        },
      );

  Widget _seekBar(Color accent) => StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (context, snap) {
          final total = player.state.duration;
          final pos = snap.data ?? Duration.zero;
          final max = total.inMilliseconds.toDouble();
          final value = (_scrub ?? pos.inMilliseconds.toDouble()).clamp(0.0, max <= 0 ? 1.0 : max);
          final shown = Duration(milliseconds: value.round());
          const style = TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()]);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text(formatDuration(shown), style: style),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: accent,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    max: max <= 0 ? 1 : max,
                    value: value,
                    onChangeStart: (v) {
                      _hideTimer?.cancel();
                      setState(() => _scrub = v);
                    },
                    onChanged: max <= 0 ? null : (v) => setState(() => _scrub = v),
                    onChangeEnd: (v) {
                      player.seek(Duration(milliseconds: v.round()));
                      setState(() => _scrub = null);
                      _scheduleHide();
                    },
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _showRemaining = !_showRemaining),
                child: Text(
                    _showRemaining
                        ? '-${formatDuration(total - shown)}'
                        : formatDuration(total),
                    style: style),
              ),
            ]),
          );
        },
      );

  Widget _bottomRow() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Row(children: [
          _icon(Icons.lock_open_rounded, () {
            setState(() {
              _locked = true;
              _controlsVisible = false;
              _lockHintVisible = true;
            });
            _hideTimer?.cancel();
            _hideTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) setState(() => _lockHintVisible = false);
            });
          }, tip: 'Lock screen'),
          _icon((_rotation ?? Rotation.auto).icon, () {
            final next = Rotation.values[
                ((_rotation?.index ?? 2) + 1) % Rotation.values.length];
            _applyRotation(next);
            _flash(next.icon, next.label);
          }, tip: 'Rotation'),
          const Spacer(),
          _icon(Icons.headphones_rounded, _playInBackground, tip: 'Play audio in background'),
          _icon(_fit.icon, () {
            setState(() {
              _fit = FitMode.values[(_fit.index + 1) % FitMode.values.length];
              _zoom = 1;
            });
            _flash(_fit.icon, _fit.label);
          }, tip: 'Screen fit'),
        ]),
      );

  // Sheets ------------------------------------------------------------------

  Future<void> _sheet(WidgetBuilder builder) async {
    _hideTimer?.cancel();
    await showPlayerSheet<void>(context, builder);
    if (mounted) {
      setState(() {});
      _scheduleHide();
    }
  }

  void _openSpeed() => _sheet((_) => SpeedSheet(player: player, settings: settings));
  void _openAudio() => _sheet((_) => AudioTrackSheet(player: player));
  void _openSubtitles() =>
      _sheet((_) => SubtitleSheet(player: player, settings: settings));

  void _openMore() => _sheet((ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.headphones_rounded),
            title: const Text('Play audio in background'),
            subtitle: const Text('Keeps playing with the screen off'),
            onTap: () {
              Navigator.pop(ctx);
              _playInBackground();
            },
          ),
          if (_pipSupported)
            ListTile(
              leading: const Icon(Icons.picture_in_picture_alt_rounded),
              title: const Text('Picture-in-picture'),
              onTap: () {
                Navigator.pop(ctx);
                _enterPip();
              },
            ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Video info'),
            onTap: () {
              Navigator.pop(ctx);
              _showInfo();
            },
          ),
        ]),
      ));

  void _showInfo() {
    final s = player.state;
    final v = s.videoParams;
    final a = s.audioParams;
    _sheet((ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: const Text('Name'), subtitle: Text(item.title)),
            ListTile(
                title: const Text('Duration'), subtitle: Text(formatDuration(s.duration))),
            if (s.width != null)
              ListTile(
                  title: const Text('Resolution'),
                  subtitle: Text('${s.width} × ${s.height}')),
            if (v.pixelformat != null)
              ListTile(title: const Text('Video'), subtitle: Text('${v.pixelformat}')),
            if (a.format != null)
              ListTile(
                  title: const Text('Audio'),
                  subtitle: Text([
                    a.format,
                    if (a.sampleRate != null) '${a.sampleRate} Hz',
                    if (a.channelCount != null) '${a.channelCount} ch',
                  ].join(' · '))),
            ListTile(
                title: const Text('Location'),
                subtitle: Text(item.path ?? item.uri,
                    maxLines: 3, overflow: TextOverflow.ellipsis)),
          ]),
        ));
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.top});
  final bool top;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
            ),
          ),
        ),
      );
}
