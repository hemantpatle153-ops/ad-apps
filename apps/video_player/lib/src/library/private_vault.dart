import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../settings.dart';
import 'video_library.dart';

/// A video moved into the private folder.
class PrivateVideo {
  PrivateVideo(this.file, this.title, this.originalFolder);

  final File file;
  final String title;

  /// Relative folder ("Movies/Trip/") it came from, to put it back there.
  final String originalFolder;

  int get size {
    try {
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }
}

/// PIN-locked folder inside the app's own storage. Videos moved here leave
/// the gallery and other apps until they are moved back out.
class PrivateVault extends ChangeNotifier {
  PrivateVault(this._settings);

  final Settings _settings;
  Directory? _dir;
  List<PrivateVideo> videos = [];

  bool get hasPin => _settings.pinHash != null;

  static String hashPin(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  void setPin(String pin) {
    final r = Random.secure();
    final salt = base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
    _settings.setPin(salt, hashPin(salt, pin));
    notifyListeners();
  }

  bool checkPin(String pin) {
    final salt = _settings.pinSalt, hash = _settings.pinHash;
    return salt != null && hash != null && hashPin(salt, pin) == hash;
  }

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'private'));
    await d.create(recursive: true);
    return _dir = d;
  }

  File _metaFile(Directory d) => File(p.join(d.path, 'index.json'));

  Future<Map<String, String>> _readMeta(Directory d) async {
    try {
      final j = jsonDecode(await _metaFile(d).readAsString()) as Map;
      return j.map((k, v) => MapEntry(k as String, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMeta(Directory d, Map<String, String> meta) =>
      _metaFile(d).writeAsString(jsonEncode(meta));

  Future<void> load() async {
    final d = await _folder();
    final meta = await _readMeta(d);
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path) != 'index.json')
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    videos = [
      for (final f in files)
        PrivateVideo(f, p.basename(f.path), meta[p.basename(f.path)] ?? 'Movies/'),
    ];
    notifyListeners();
  }

  /// Copies the video in, then deletes the original (Android asks the user
  /// to confirm). If the user says no, the copy is removed again.
  Future<bool> hide(VideoEntry v) async {
    final d = await _folder();
    File? source;
    final guess = v.path;
    if (guess != null && await File(guess).exists()) source = File(guess);
    source ??= await v.asset.originFile;
    if (source == null) return false;
    var name = v.title;
    var target = File(p.join(d.path, name));
    for (var i = 1; await target.exists(); i++) {
      name = '${p.basenameWithoutExtension(v.title)} ($i)${p.extension(v.title)}';
      target = File(p.join(d.path, name));
    }
    await source.copy(target.path);
    final deleted = await PhotoManager.editor.deleteWithIds([v.id]);
    if (!deleted.contains(v.id)) {
      await target.delete();
      return false;
    }
    final meta = await _readMeta(d);
    meta[name] = v.asset.relativePath ?? 'Movies/';
    await _writeMeta(d, meta);
    await load();
    await VideoLibrary.instance.reload();
    return true;
  }

  /// Puts the video back in its original folder in the gallery.
  Future<bool> unhide(PrivateVideo v) async {
    try {
      await PhotoManager.editor.saveVideo(
        v.file,
        title: v.title,
        relativePath: v.originalFolder,
      );
    } catch (_) {
      return false;
    }
    await v.file.delete();
    final d = await _folder();
    final meta = await _readMeta(d)..remove(v.title);
    await _writeMeta(d, meta);
    await load();
    await VideoLibrary.instance.reload();
    return true;
  }

  Future<void> deleteForever(PrivateVideo v) async {
    await v.file.delete();
    await load();
  }

  /// "Forgot PIN": wipes the private folder and the PIN.
  Future<void> reset() async {
    final d = await _folder();
    if (await d.exists()) await d.delete(recursive: true);
    _dir = null;
    _settings.clearPin();
    videos = [];
    notifyListeners();
  }
}
