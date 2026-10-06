import 'dart:async';

import 'package:flutter/foundation.dart';

import 'platform/native.dart';
import 'settings.dart';
import 'sync/speaker.dart';

/// This phone's speaker delay for the output in use right now. Checks the
/// output every few seconds, so plugging in or connecting a Bluetooth
/// speaker mid-song switches to that speaker's delay.
class SpeakerDelay extends ChangeNotifier implements LocalSpeaker {
  SpeakerDelay(this.settings) {
    _check();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    settings.addListener(notifyListeners);
  }

  final Settings settings;
  AudioOutput output = AudioOutput.phone;
  Timer? _timer;

  int get ms => settings.delayMs(bluetooth: output.bluetooth);
  set ms(int v) => settings.setDelayMs(v, bluetooth: output.bluetooth);

  @override
  int get delayMs => ms;
  @override
  set delayMs(int v) => ms = v;

  @override
  bool get bluetooth => output.bluetooth;

  @override
  int latencyUs() => ms * 1000;

  @override
  String get outputLabel => output.bluetooth
      ? 'Bluetooth${output.name == null ? '' : ': ${output.name}'}'
      : 'Phone speaker or wired';

  Future<void> _check() async {
    final o = await Native.audioOutput();
    if (o.bluetooth != output.bluetooth || o.name != output.name) {
      output = o;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    settings.removeListener(notifyListeners);
    super.dispose();
  }
}
