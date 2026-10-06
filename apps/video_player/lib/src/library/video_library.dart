import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../settings.dart';

/// One video on the phone, read from the system media store.
class VideoEntry {
  VideoEntry(this.asset, this.folder);

  final AssetEntity asset;
  final String folder;

  /// File size in bytes, filled in the background after the list loads.
  int size = 0;

  String get id => asset.id;
  String get title => asset.title ?? 'Video';
  Duration get duration => asset.videoDuration;
  int get width => asset.orientatedWidth;
  int get height => asset.orientatedHeight;
  DateTime get modified => asset.modifiedDateTime;
  DateTime get created => asset.createDateTime;

  /// Best guess at the file's path, used to look for a matching .srt file.
  String? get path {
    final rel = asset.relativePath;
    if (rel == null || asset.title == null) return null;
    if (rel.startsWith('/')) return '$rel/${asset.title}'.replaceAll('//', '/');
    return '/storage/emulated/0/$rel${rel.endsWith('/') ? '' : '/'}${asset.title}';
  }

  bool matches(String query) => title.toLowerCase().contains(query.toLowerCase());
}

/// A folder (media store bucket) and the videos in it.
class VideoFolder {
  VideoFolder(this.id, this.name, this.videos);

  final String id;
  final String name;
  final List<VideoEntry> videos;

  int get totalSize => videos.fold(0, (sum, v) => sum + v.size);
  Duration get totalDuration =>
      videos.fold(Duration.zero, (sum, v) => sum + v.duration);
  DateTime get latest => videos
      .map((v) => v.modified)
      .fold(DateTime.fromMillisecondsSinceEpoch(0), (a, b) => b.isAfter(a) ? b : a);
}

enum LibraryState { loading, noPermission, ready }

/// Finds every video on the phone and keeps the list up to date.
class VideoLibrary extends ChangeNotifier {
  VideoLibrary._();

  static final VideoLibrary instance = VideoLibrary._();

  LibraryState state = LibraryState.loading;
  bool limitedAccess = false;
  List<VideoFolder> folders = [];
  bool _listening = false;
  Timer? _debounce;
  int _generation = 0;

  List<VideoEntry> get all => [for (final f in folders) ...f.videos];

  VideoEntry? byId(String id) {
    for (final f in folders) {
      for (final v in f.videos) {
        if (v.id == id) return v;
      }
    }
    return null;
  }

  static const _permission = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.video,
      mediaLocation: false,
    ),
  );

  /// Asks for video access if needed, then loads the library.
  Future<void> start({bool ask = true}) async {
    final ps = ask
        ? await PhotoManager.requestPermissionExtend(requestOption: _permission)
        : await PhotoManager.getPermissionState(requestOption: _permission);
    if (!ps.hasAccess) {
      state = LibraryState.noPermission;
      notifyListeners();
      return;
    }
    limitedAccess = ps == PermissionState.limited;
    if (!_listening) {
      _listening = true;
      PhotoManager.addChangeCallback((_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 800), reload);
      });
      PhotoManager.startChangeNotify();
    }
    await reload();
  }

  Future<void> openSettings() => PhotoManager.openSetting();

  Future<void> reload() async {
    final gen = ++_generation;
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: false,
      filterOption: FilterOptionGroup(
        videoOption: const FilterOption(
          durationConstraint: DurationConstraint(max: Duration(days: 2)),
        ),
        orders: [const OrderOption(type: OrderOptionType.updateDate, asc: false)],
      ),
    );
    final old = {for (final v in all) v.id: v.size};
    final result = <VideoFolder>[];
    for (final p in paths) {
      final count = await p.assetCountAsync;
      if (count == 0) continue;
      final assets = await p.getAssetListRange(start: 0, end: count);
      final videos = [for (final a in assets) VideoEntry(a, p.name)];
      for (final v in videos) {
        v.size = old[v.id] ?? 0;
      }
      result.add(VideoFolder(p.id, p.name.isEmpty ? 'Internal storage' : p.name, videos));
    }
    if (gen != _generation) return;
    folders = result;
    state = LibraryState.ready;
    notifyListeners();
    unawaited(_loadSizes(gen));
  }

  /// File sizes need one call per video, so they load after the list shows.
  Future<void> _loadSizes(int gen) async {
    final missing = all.where((v) => v.size == 0).toList();
    for (var i = 0; i < missing.length; i += 24) {
      if (gen != _generation) return;
      final chunk = missing.skip(i).take(24);
      await Future.wait(chunk.map((v) async {
        try {
          v.size = await v.asset.fileSize;
        } catch (_) {}
      }));
      if (i % 96 == 0 || i + 24 >= missing.length) notifyListeners();
    }
  }

  /// Deletes videos after the system's own confirmation dialog.
  /// Returns the ids that were actually deleted.
  Future<List<String>> delete(List<String> ids) async {
    final done = await PhotoManager.editor.deleteWithIds(ids);
    if (done.isNotEmpty) await reload();
    return done;
  }

  // Sorting ----------------------------------------------------------------

  static List<VideoEntry> sortVideos(
      List<VideoEntry> videos, VideoSort sort, bool desc) {
    final list = [...videos];
    int cmp(VideoEntry a, VideoEntry b) => switch (sort) {
          VideoSort.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          VideoSort.date => a.modified.compareTo(b.modified),
          VideoSort.size => a.size.compareTo(b.size),
          VideoSort.duration => a.duration.compareTo(b.duration),
        };
    list.sort((a, b) => desc ? cmp(b, a) : cmp(a, b));
    return list;
  }

  static List<VideoFolder> sortFolders(List<VideoFolder> folders, FolderSort sort) {
    final list = [...folders];
    switch (sort) {
      case FolderSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case FolderSort.count:
        list.sort((a, b) => b.videos.length.compareTo(a.videos.length));
      case FolderSort.date:
        list.sort((a, b) => b.latest.compareTo(a.latest));
    }
    return list;
  }
}
