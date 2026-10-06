import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../library/video_library.dart';
import '../player/play_item.dart';
import '../widgets/video_thumb.dart';
import 'online.dart';

/// Orders this phone's videos so the one most likely to be the party's
/// video comes first: same length, then same name.
List<VideoEntry> rankMatches(List<VideoEntry> videos, OnlineVideo target) {
  int score(VideoEntry v) {
    var s = (v.duration.inMilliseconds - target.durationMs).abs();
    if (v.title.toLowerCase() == target.title.toLowerCase()) s -= 5000;
    return s;
  }

  return [...videos]..sort((a, b) => score(a).compareTo(score(b)));
}

/// True when [d] is close enough to the party video's length to be it.
bool sameLength(Duration d, int targetMs) =>
    targetMs <= 0 || (d.inMilliseconds - targetMs).abs() <= 3000;

/// A friend joining an online party picks their own copy of the video.
/// Returns what to play, or null if they backed out.
class PickVideoScreen extends StatefulWidget {
  const PickVideoScreen({super.key, required this.video});

  final OnlineVideo video;

  @override
  State<PickVideoScreen> createState() => _PickVideoScreenState();
}

class _PickVideoScreenState extends State<PickVideoScreen> {
  final library = VideoLibrary.instance;

  PlayItem _item(String uri, String title, {String? path}) =>
      PlayItem(uri: uri, title: title, key: 'party', path: path, transient: true);

  Future<void> _pickFile() async {
    final res = await FilePicker.pickFiles(type: FileType.video);
    final f = res.firstOrNull;
    final path = f?.path;
    if (path == null || !mounted) return;
    Navigator.pop(context, _item(path, f!.name, path: path));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = widget.video;
    return Scaffold(
      appBar: AppBar(title: const Text('Pick your copy')),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final videos = rankMatches(library.all, target);
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Your friend is watching "${target.title}"'
                '${target.durationMs > 0 ? ' (${formatDuration(Duration(milliseconds: target.durationMs))})' : ''}. '
                'Pick the same video on this phone. Only play, pause and seek '
                'go over the internet, so it plays smoothly.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Choose a file'),
              subtitle: const Text('If it is not in the list below'),
              onTap: _pickFile,
            ),
            if (library.state == LibraryState.loading)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator())),
            if (library.state == LibraryState.noPermission)
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Allow access to your videos'),
                onTap: library.start,
              ),
            for (final v in videos.take(60))
              ListTile(
                leading: VideoThumb(assetId: v.id, width: 96, height: 54, radius: 8),
                title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatDuration(v.duration)),
                trailing: sameLength(v.duration, target.durationMs) && target.durationMs > 0
                    ? Chip(
                        label: const Text('Same length'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                      )
                    : null,
                onTap: () {
                  final e = PlayItem.fromEntry(v);
                  Navigator.pop(context, _item(e.uri, e.title, path: e.path));
                },
              ),
          ]);
        },
      ),
    );
  }
}
