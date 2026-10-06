import 'package:flutter/services.dart';

/// What is playing the sound on this phone right now.
class AudioOutput {
  const AudioOutput({required this.bluetooth, this.name});

  static const phone = AudioOutput(bluetooth: false);

  final bool bluetooth;

  /// The Bluetooth speaker's name, when there is one.
  final String? name;
}

/// Small Android helpers in MainActivity.kt. Every call is safe when the
/// native side is missing (tests): it just returns a harmless default.
class Native {
  Native._();

  static const _channel = MethodChannel('in.onlysoftware.multi_speaker/native');

  /// Keeps Wi-Fi awake and listening to beacons while a party runs, so the
  /// sound doesn't stutter when the screen goes off.
  static Future<void> holdNetwork(bool on) =>
      _call<void>(on ? 'holdNetwork' : 'releaseNetwork');

  static Future<void> openBluetoothSettings() =>
      _call<void>('openBluetoothSettings');

  /// Opens the system "play on" panel (Samsung Dual audio lives there).
  static Future<void> openMediaOutput() => _call<void>('openMediaOutput');

  /// Opens the hotspot settings page (falls back to Wi-Fi settings).
  static Future<void> openHotspotSettings() => _call<void>('openHotspotSettings');

  static Future<String> deviceName() async =>
      await _call<String>('deviceName') ?? 'Phone';

  static Future<AudioOutput> audioOutput() async {
    final m = await _call<Map<Object?, Object?>>('audioOutput');
    if (m == null) return AudioOutput.phone;
    return AudioOutput(
        bluetooth: m['bluetooth'] == true, name: m['name'] as String?);
  }

  /// What this phone offers for playing to more than one Bluetooth speaker
  /// by itself: LE Audio broadcast ("Audio sharing", Auracast) and the
  /// maker's name (Samsung phones have "Dual audio").
  static Future<({bool leAudioBroadcast, String maker})> bluetoothFeatures() async {
    final m = await _call<Map<Object?, Object?>>('bluetoothFeatures');
    return (
      leAudioBroadcast: m?['leAudioBroadcast'] == true,
      maker: (m?['maker'] as String? ?? '').toLowerCase(),
    );
  }

  static Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
