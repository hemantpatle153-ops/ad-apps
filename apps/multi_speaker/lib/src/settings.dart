import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved choices. The speaker delay is kept separately for the phone's own
/// speaker and for Bluetooth, since a Bluetooth speaker adds its own lag.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  final SharedPreferences _prefs;

  /// A typical Bluetooth speaker plays about 200 ms after the phone.
  static const defaultBluetoothDelayMs = 200;
  static const maxDelayMs = 600;

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  String? get name => _prefs.getString('name');
  set name(String? v) {
    if (v == null || v.trim().isEmpty) {
      _prefs.remove('name');
    } else {
      _prefs.setString('name', v.trim());
    }
    notifyListeners();
  }

  int delayMs({required bool bluetooth}) => bluetooth
      ? _prefs.getInt('delay_bt') ?? defaultBluetoothDelayMs
      : _prefs.getInt('delay_phone') ?? 0;

  void setDelayMs(int ms, {required bool bluetooth}) {
    _prefs.setInt(bluetooth ? 'delay_bt' : 'delay_phone',
        ms.clamp(0, maxDelayMs).toInt());
    notifyListeners();
  }

  bool get seenIntro => _prefs.getBool('seen_intro') ?? false;
  set seenIntro(bool v) => _prefs.setBool('seen_intro', v);
}
