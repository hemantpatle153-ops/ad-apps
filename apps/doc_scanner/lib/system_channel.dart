import 'package:flutter/services.dart';

/// A file another app opened with or shared to Doc Scanner, copied into
/// the app's cache by MainActivity.
class SharedFile {
  const SharedFile(this.path, this.mime, this.name);
  final String path;
  final String mime;
  final String name;

  bool get isPdf => mime.contains('pdf') || name.toLowerCase().endsWith('.pdf');
  bool get isImage => mime.startsWith('image/');

  static SharedFile fromMap(Map<Object?, Object?> m) => SharedFile(
      '${m['path'] ?? ''}', '${m['mime'] ?? ''}', '${m['name'] ?? ''}');
}

/// Small bridge to Android for things no plugin is needed for.
class SystemChannel {
  SystemChannel._();
  static const _ch = MethodChannel('in.onlysoftware.doc_scanner/system');

  /// Files from the intent that launched the app (returned once).
  static Future<List<SharedFile>> takeSharedFiles() async {
    try {
      final list = await _ch.invokeListMethod<Object?>('takeSharedFiles') ?? const [];
      return [for (final m in list) SharedFile.fromMap(m as Map<Object?, Object?>)];
    } catch (_) {
      return const [];
    }
  }

  /// Calls [onShared] when files arrive while the app is open.
  static void listen(void Function(List<SharedFile>) onShared) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared') {
        final list = (call.arguments as List?) ?? const [];
        onShared([for (final m in list) SharedFile.fromMap(m as Map<Object?, Object?>)]);
      }
    });
  }

  static Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod('openAppSettings');
    } catch (_) {}
  }
}
