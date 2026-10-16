import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Camera choices the app remembers between scans, kept in a small file in
/// the app's private folder.
class ScanSettings {
  ScanSettings._();

  /// Crop each document scan to the page edges it finds.
  static bool autoCrop = true;

  static bool _loaded = false;

  static Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/scan_settings.json');

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      autoCrop = m['autoCrop'] as bool? ?? autoCrop;
    } catch (_) {
      // A damaged settings file just means the defaults.
    }
  }

  static Future<void> save() async {
    try {
      await (await _file()).writeAsString(jsonEncode({'autoCrop': autoCrop}), flush: true);
    } catch (_) {}
  }
}
