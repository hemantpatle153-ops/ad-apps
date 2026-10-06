import 'package:flutter/foundation.dart';

/// This phone's own speaker as the party sees it: the output in use and
/// its sync delay. The app backs it with saved settings and the Android
/// output check; tests use a plain one.
abstract class LocalSpeaker implements Listenable {
  int get delayMs;
  set delayMs(int ms);

  /// Like "Bluetooth: JBL Flip 5" or "Phone speaker or wired".
  String get outputLabel;
  bool get bluetooth;

  int latencyUs() => delayMs * 1000;
}

/// A [LocalSpeaker] that only remembers its values.
class SimpleSpeaker extends ChangeNotifier implements LocalSpeaker {
  SimpleSpeaker({this._delayMs = 0, this.outputLabel = 'Phone speaker', this.bluetooth = false});

  int _delayMs;
  @override
  final String outputLabel;
  @override
  final bool bluetooth;

  @override
  int get delayMs => _delayMs;
  @override
  set delayMs(int ms) {
    _delayMs = ms;
    notifyListeners();
  }

  @override
  int latencyUs() => _delayMs * 1000;
}

/// Volume and mute for one speaker, shared by host and guest.
class SpeakerLevel {
  const SpeakerLevel({this.volume = 1, this.muted = false});

  /// 0..1.
  final double volume;
  final bool muted;

  double get effective => muted ? 0 : volume;

  SpeakerLevel copyWith({double? volume, bool? muted}) =>
      SpeakerLevel(volume: volume ?? this.volume, muted: muted ?? this.muted);
}
