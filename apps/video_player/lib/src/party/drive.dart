import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Streams a video to an online watch party through the host's own Google
/// Drive, so friends don't need a copy of the file.
///
/// The host uploads the video once into a "Video Player parties" folder.
/// While a party runs the file is readable by anyone with its link (the link
/// only travels inside the room, which only people with the code can read);
/// when the party ends it goes private again. Uploads are deleted from Drive
/// after [keepFor], so a movie can be reused the same day without uploading
/// it again.
///
/// The app asks only for `drive.file`: it sees the files it created and
/// nothing else in the user's Drive.
class DriveShare {
  DriveShare._();

  static final instance = DriveShare._();

  /// A Google Cloud API key allowed to call the Drive API. Guests use it to
  /// read the shared file without signing in. Builds without it don't offer
  /// Drive streaming.
  static const apiKey = String.fromEnvironment('DRIVE_API_KEY');

  static bool get available => apiKey.isNotEmpty;

  static const _scopes = ['https://www.googleapis.com/auth/drive.file'];
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _uploadApi = 'https://www.googleapis.com/upload/drive/v3';
  static const _folderName = 'Video Player parties';

  /// Marks every file and folder this feature creates, so cleanup only
  /// touches its own uploads.
  static const _tag = 'vpParty';

  static const keepFor = Duration(hours: 24);

  /// Upload chunk size; must be a multiple of 256 KiB.
  static const _chunk = 8 * 1024 * 1024;

  bool _initialized = false;

  /// The link guests open. Drive answers range requests, so seeking works.
  static String streamUrl(String fileId) =>
      '$_api/files/$fileId?alt=media&key=$apiKey';

  Future<GoogleSignInAuthorizationClient> _client() async {
    if (!_initialized) {
      await GoogleSignIn.instance.initialize();
      _initialized = true;
    }
    return GoogleSignIn.instance.authorizationClient;
  }

  /// Asks the user to pick a Google account and allow Drive access, once.
  /// Later calls return a fresh token without asking again.
  Future<String> _token({bool prompt = true}) async {
    final client = await _client();
    try {
      final silent = await client.authorizationForScopes(_scopes);
      if (silent != null) return silent.accessToken;
      if (!prompt) throw const DriveException(DriveError.signIn);
      return (await client.authorizeScopes(_scopes)).accessToken;
    } on GoogleSignInException catch (e) {
      throw DriveException(
          e.code == GoogleSignInExceptionCode.canceled
              ? DriveError.canceled
              : DriveError.signIn,
          e.description ?? e.code.name);
    }
  }

  Future<Map<String, String>> _headers({bool json = false}) async => {
        'Authorization': 'Bearer ${await _token()}',
        if (json) 'Content-Type': 'application/json; charset=UTF-8',
      };

  /// Turns an HTTP failure into a [DriveException].
  Never _fail(http.BaseResponse r, [String? body]) {
    final code = r.statusCode;
    if (code == 401) throw DriveException(DriveError.signIn, '$code');
    if (code == 403 && (body ?? '').contains('storageQuotaExceeded')) {
      throw DriveException(DriveError.full, '$code');
    }
    throw DriveException(DriveError.failed, '$code');
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(const Duration(seconds: 60));
    } on DriveException {
      rethrow;
    } on SocketException {
      throw const DriveException(DriveError.offline);
    } on TimeoutException {
      throw const DriveException(DriveError.offline);
    } on http.ClientException {
      throw const DriveException(DriveError.offline);
    }
  }

  Future<String> _folder() async {
    final q = "name = '$_folderName' and mimeType = 'application/vnd.google-apps.folder' "
        "and appProperties has { key='$_tag' and value='1' } and trashed = false";
    final found = await _send(() async => http.get(
        Uri.parse('$_api/files').replace(
            queryParameters: {'q': q, 'fields': 'files(id)', 'spaces': 'drive'}),
        headers: await _headers()));
    if (found.statusCode != 200) _fail(found, found.body);
    final files = (jsonDecode(found.body)['files'] as List?) ?? const [];
    if (files.isNotEmpty) return files.first['id'] as String;
    final made = await _send(() async => http.post(Uri.parse('$_api/files?fields=id'),
        headers: await _headers(json: true),
        body: jsonEncode({
          'name': _folderName,
          'mimeType': 'application/vnd.google-apps.folder',
          'appProperties': {_tag: '1'},
        })));
    if (made.statusCode != 200) _fail(made, made.body);
    return jsonDecode(made.body)['id'] as String;
  }

  static String _cacheKey(File f, int size) => 'drive:${f.path}:$size';

  /// Set once the user has uploaded anything, so [cleanup] stays off the
  /// network for everyone else.
  static const _usedKey = 'drive:used';

  /// Uploads [file] (or finds the copy uploaded earlier today) and returns
  /// its Drive file id. [onProgress] gets 0..1. Completing [cancel] stops the
  /// upload; it can be resumed by calling this again.
  Future<String> upload(File file,
      {void Function(double)? onProgress, Future<void>? cancel}) async {
    final size = await file.length();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_usedKey, true);
    final key = _cacheKey(file, size);

    final cached = prefs.getString('$key:id');
    if (cached != null && await _exists(cached)) {
      onProgress?.call(1);
      return cached;
    }
    await prefs.remove('$key:id');

    var canceled = false;
    unawaited(cancel?.then((_) => canceled = true));

    var session = prefs.getString('$key:session');
    var sent = session == null ? -1 : await _uploadedSoFar(session, size);
    if (sent < 0) {
      session = await _startSession(file, size);
      await prefs.setString('$key:session', session);
      sent = 0;
    }

    final raf = await file.open();
    try {
      var failures = 0;
      while (true) {
        onProgress?.call(size == 0 ? 1 : sent / size);
        if (canceled) throw const DriveException(DriveError.canceled);
        final end = (sent + _chunk < size ? sent + _chunk : size) - 1;
        await raf.setPosition(sent);
        final bytes = size == 0 ? <int>[] : await raf.read(end - sent + 1);
        http.Response r;
        try {
          r = await _send(() async => http.put(Uri.parse(session!),
              headers: {
                ...await _headers(),
                'Content-Range':
                    size == 0 ? 'bytes */0' : 'bytes $sent-$end/$size',
              },
              body: bytes));
        } on DriveException catch (e) {
          if (e.error != DriveError.offline || ++failures > 5) rethrow;
          await Future<void>.delayed(Duration(seconds: 2 << failures));
          final at = await _uploadedSoFar(session!, size);
          if (at < 0) rethrow;
          sent = at;
          continue;
        }
        failures = 0;
        if (r.statusCode == 200 || r.statusCode == 201) {
          final id = jsonDecode(r.body)['id'] as String;
          await prefs.setString('$key:id', id);
          await prefs.remove('$key:session');
          onProgress?.call(1);
          return id;
        }
        if (r.statusCode == 308) {
          sent = nextByte(r.headers['range']);
          continue;
        }
        if (r.statusCode == 404 || r.statusCode == 410) {
          // The upload session expired; start over next time.
          await prefs.remove('$key:session');
        }
        _fail(r, r.body);
      }
    } finally {
      await raf.close();
    }
  }

  Future<String> _startSession(File file, int size) async {
    final folder = await _folder();
    final r = await _send(() async => http.post(
        Uri.parse('$_uploadApi/files?uploadType=resumable&fields=id'),
        headers: {
          ...await _headers(json: true),
          'X-Upload-Content-Length': '$size',
          'X-Upload-Content-Type': _mimeType(file.path),
        },
        body: jsonEncode({
          'name': p.basename(file.path),
          'parents': [folder],
          'appProperties': {_tag: '1'},
        })));
    final location = r.headers['location'];
    if (r.statusCode != 200 || location == null) _fail(r, r.body);
    return location;
  }

  /// How many bytes Drive already has for an unfinished upload, or -1 if the
  /// session can't be resumed.
  Future<int> _uploadedSoFar(String session, int size) async {
    try {
      final r = await _send(() async => http.put(Uri.parse(session),
          headers: {...await _headers(), 'Content-Range': 'bytes */$size'}));
      if (r.statusCode == 308) return nextByte(r.headers['range']);
      return -1;
    } on DriveException catch (e) {
      if (e.error == DriveError.canceled || e.error == DriveError.signIn) rethrow;
      return -1;
    }
  }

  /// Drive reports what it has as "bytes=0-1234"; the next byte to send is
  /// one past the end. No header means nothing arrived yet.
  @visibleForTesting
  static int nextByte(String? range) {
    final m = RegExp(r'bytes=0-(\d+)').firstMatch(range ?? '');
    return m == null ? 0 : int.parse(m.group(1)!) + 1;
  }

  Future<bool> _exists(String id) async {
    final r = await _send(() async => http.get(
        Uri.parse('$_api/files/$id?fields=id,trashed'),
        headers: await _headers()));
    return r.statusCode == 200 && jsonDecode(r.body)['trashed'] != true;
  }

  /// Lets anyone with the link read the file, for the length of a party.
  Future<void> share(String id) async {
    final r = await _send(() async => http.post(
        Uri.parse('$_api/files/$id/permissions?fields=id'),
        headers: await _headers(json: true),
        body: jsonEncode({'role': 'reader', 'type': 'anyone'})));
    if (r.statusCode != 200) _fail(r, r.body);
  }

  /// Makes the file private again. Never asks the user to sign in.
  Future<void> unshare(String id) async {
    try {
      final h = {'Authorization': 'Bearer ${await _token(prompt: false)}'};
      await _send(() => http.delete(
          Uri.parse('$_api/files/$id/permissions/anyoneWithLink'),
          headers: h));
    } on DriveException {
      // Signed out or offline: cleanup removes the file later anyway.
    }
  }

  /// Deletes this feature's uploads older than [keepFor]. Never asks the user
  /// to sign in; does nothing if they never used Drive streaming.
  Future<void> cleanup() async {
    if (!available) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_usedKey) != true) return;
      final token = await _token(prompt: false);
      final before = DateTime.now().toUtc().subtract(keepFor).toIso8601String();
      final q = "appProperties has { key='$_tag' and value='1' } and "
          "mimeType != 'application/vnd.google-apps.folder' and "
          "createdTime < '$before'";
      final r = await _send(() => http.get(
          Uri.parse('$_api/files').replace(
              queryParameters: {'q': q, 'fields': 'files(id)', 'pageSize': '50'}),
          headers: {'Authorization': 'Bearer $token'}));
      if (r.statusCode != 200) return;
      for (final f in (jsonDecode(r.body)['files'] as List? ?? const [])) {
        await _send(() => http.delete(Uri.parse('$_api/files/${f['id']}'),
            headers: {'Authorization': 'Bearer $token'}));
      }
    } catch (_) {
      // Next time.
    }
  }

  static String _mimeType(String path) => switch (p.extension(path).toLowerCase()) {
        '.mp4' || '.m4v' => 'video/mp4',
        '.mkv' => 'video/x-matroska',
        '.webm' => 'video/webm',
        '.mov' => 'video/quicktime',
        '.avi' => 'video/x-msvideo',
        '.3gp' => 'video/3gpp',
        '.ts' => 'video/mp2t',
        _ => 'application/octet-stream',
      };
}

enum DriveError { canceled, signIn, offline, full, failed }

class DriveException implements Exception {
  const DriveException(this.error, [this.code]);

  final DriveError error;
  final String? code;

  String get message => switch (error) {
        DriveError.canceled => 'Upload stopped. Start again to continue where it left off.',
        DriveError.signIn => "Couldn't sign in to Google Drive. ($code)",
        DriveError.offline =>
          "Couldn't reach Google Drive. Check your connection and try again; "
              'the upload continues where it stopped.',
        DriveError.full => 'Your Google Drive is full. Free up space and try again.',
        DriveError.failed => 'Google Drive said no. Try again. ($code)',
      };

  @override
  String toString() => 'DriveException($error, $code)';
}
