import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../library/private_vault.dart';
import '../library/video_library.dart';
import '../player/play_item.dart';
import '../player/player_screen.dart';
import '../settings.dart';
import '../widgets/video_tile.dart';
import 'video_actions.dart';

/// The videos in one folder, with sorting.
class FolderScreen extends StatelessWidget {
  const FolderScreen({
    super.key,
    required this.folderId,
    required this.settings,
    required this.vault,
  });

  final String folderId;
  final Settings settings;
  final PrivateVault vault;

  @override
  Widget build(BuildContext context) {
    final library = VideoLibrary.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([library, settings]),
      builder: (context, _) {
        final folder = library.folders.where((f) => f.id == folderId).firstOrNull;
        final videos = folder == null
            ? <VideoEntry>[]
            : VideoLibrary.sortVideos(folder.videos, settings.videoSort, settings.videoSortDesc);
        return Scaffold(
          appBar: AppBar(
            title: Text(folder?.name ?? 'Folder'),
            actions: [
              PopupMenuButton<VideoSort>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort_rounded),
                onSelected: (s) => settings.setVideoSort(
                    s, s == settings.videoSort ? !settings.videoSortDesc : s != VideoSort.name),
                itemBuilder: (_) => [
                  for (final (s, label) in const [
                    (VideoSort.name, 'Name'),
                    (VideoSort.date, 'Date'),
                    (VideoSort.size, 'Size'),
                    (VideoSort.duration, 'Length'),
                  ])
                    PopupMenuItem(
                      value: s,
                      child: Row(children: [
                        Expanded(child: Text(label)),
                        if (s == settings.videoSort)
                          Icon(settings.videoSortDesc
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded, size: 18),
                      ]),
                    ),
                ],
              ),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: videos.isEmpty
                  ? const Center(child: Text('No videos here'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: videos.length,
                      itemBuilder: (context, i) => VideoTile(
                        video: videos[i],
                        settings: settings,
                        onTap: () => openPlayer(
                          context,
                          settings,
                          [for (final v in videos) PlayItem.fromEntry(v)],
                          index: i,
                        ),
                        onMore: () => showVideoActions(context,
                            video: videos[i], settings: settings, vault: vault),
                      ),
                    ),
            ),
            const BannerAdSlot(),
          ]),
        );
      },
    );
  }
}
