import '../library/private_vault.dart';
import '../library/video_library.dart';
import '../settings.dart';

/// Anything the player can open: a phone video, a private one, a link.
class PlayItem {
  const PlayItem({
    required this.uri,
    required this.title,
    required this.key,
    this.assetId,
    this.path,
    this.isPrivate = false,
  });

  /// Private-folder videos stay out of the recent list.
  final bool isPrivate;

  /// content://, file path or http(s) url.
  final String uri;
  final String title;

  /// Identity for resume points and the recent list.
  final String key;
  final String? assetId;

  /// Real file path when known, to find a matching subtitle file.
  final String? path;

  bool get isNetwork => uri.startsWith('http');

  /// Phone videos play through their content:// uri, which works on every
  /// Android version without file access.
  static PlayItem fromEntry(VideoEntry v) => PlayItem(
        uri: 'content://media/external/video/media/${v.id}',
        title: v.title,
        key: v.id,
        assetId: v.id,
        path: v.path,
      );

  static PlayItem fromPrivate(PrivateVideo v) => PlayItem(
        uri: v.file.path,
        title: v.title,
        key: 'private:${v.title}',
        path: v.file.path,
        isPrivate: true,
      );

  static PlayItem fromRecent(RecentItem r) => PlayItem(
        uri: r.uri,
        title: r.title,
        key: r.key,
        assetId: r.assetId,
        path: VideoLibrary.instance.byId(r.assetId ?? '')?.path,
      );

  static PlayItem fromUrl(String url) {
    final u = Uri.tryParse(url);
    var title = url;
    if (u != null && u.pathSegments.isNotEmpty && u.pathSegments.last.isNotEmpty) {
      title = Uri.decodeComponent(u.pathSegments.last);
    } else if (u != null && u.host.isNotEmpty) {
      title = u.host;
    }
    return PlayItem(uri: url, title: title, key: url);
  }

  /// A video another app asked us to open.
  static PlayItem fromExternal(String uri) {
    final u = Uri.tryParse(uri);
    var title = 'Video';
    if (u != null && u.pathSegments.isNotEmpty) {
      title = Uri.decodeComponent(u.pathSegments.last);
      final slash = title.lastIndexOf('/');
      if (slash >= 0) title = title.substring(slash + 1);
    }
    return PlayItem(
      uri: uri,
      title: title,
      key: uri,
      path: u?.scheme == 'file' ? u!.toFilePath() : null,
    );
  }
}
