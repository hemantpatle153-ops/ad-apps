import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to MainActivity: picture-in-picture, "open with", move to back.
class SystemChannel {
  SystemChannel._() {
    _channel.setMethodCallHandler(_onCall);
  }

  static final SystemChannel instance = SystemChannel._();

  static const _channel = MethodChannel('in.onlysoftware.video_player/system');

  /// True while the app shows as a small picture-in-picture window.
  final ValueNotifier<bool> inPip = ValueNotifier(false);

  /// Called with a video uri another app asked us to open.
  void Function(String uri)? onOpenUri;
  String? _lastUri;
  DateTime _lastUriAt = DateTime(2000);

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'pipChanged':
        inPip.value = call.arguments == true;
      case 'openUri':
        _deliver(call.arguments as String?);
    }
    return null;
  }

  void _deliver(String? uri) {
    if (uri == null) return;
    // The same intent can arrive both pushed and pulled on a cold start.
    final now = DateTime.now();
    if (uri == _lastUri && now.difference(_lastUriAt).inSeconds < 3) return;
    _lastUri = uri;
    _lastUriAt = now;
    onOpenUri?.call(uri);
  }

  /// Picks up the video this app was launched to open, if any.
  Future<void> takeOpenedUri() async {
    for (var i = 0; i < 5; i++) {
      try {
        _deliver(await _channel.invokeMethod<String>('takeOpenedUri'));
        return;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } catch (_) {
        return;
      }
    }
  }

  bool? _pipSupported;

  Future<bool> pipSupported() async {
    try {
      return _pipSupported ??=
          await _channel.invokeMethod<bool>('pipSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enterPip(int? w, int? h) async {
    try {
      return await _channel.invokeMethod<bool>('enterPip', {'w': w, 'h': h}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAutoPip(bool enabled, int? w, int? h) async {
    try {
      await _channel
          .invokeMethod('setAutoPip', {'enabled': enabled, 'w': w, 'h': h});
    } catch (_) {}
  }

  /// Loudness of the video's sound per [frameMs] from [startMs], for
  /// subtitle auto sync. Throws when the sound can't be decoded.
  Future<Float32List> speechEnergy(String uri,
      {required int startMs, required int durationMs, int frameMs = 100}) async {
    final r = await _channel.invokeMethod<Float32List>('speechEnergy', {
      'uri': uri,
      'startMs': startMs,
      'durationMs': durationMs,
      'frameMs': frameMs,
    });
    if (r == null) throw StateError('no sound decoded');
    return r;
  }

  Future<void> moveToBack() async {
    try {
      await _channel.invokeMethod('moveToBack');
    } catch (_) {}
  }
}
