import 'package:flutter/material.dart';

import '../format.dart';
import '../library/video_library.dart';
import '../settings.dart';
import 'video_thumb.dart';

/// One row in a video list: thumbnail, title, size and quality.
class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.video,
    required this.settings,
    required this.onTap,
    this.onMore,
    this.showFolder = false,
  });

  final VideoEntry video;
  final Settings settings;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final bool showFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isNew = !settings.wasPlayed(video.id) &&
        DateTime.now().difference(video.created).inDays < 3;
    final meta = [
      if (showFolder) video.folder,
      formatSize(video.size),
      qualityLabel(video.width, video.height),
    ].where((s) => s.isNotEmpty).join('  ·  ');
    return InkWell(
      onTap: onTap,
      onLongPress: onMore,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(children: [
          VideoThumb(
            assetId: video.id,
            badge: formatDuration(video.duration),
            progress: settings.progressFor(video.id, video.duration),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                const SizedBox(height: 5),
                Row(children: [
                  if (isNew) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text('NEW',
                          style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ]),
              ],
            ),
          ),
          if (onMore != null)
            IconButton(
              onPressed: onMore,
              icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant),
            ),
        ]),
      ),
    );
  }
}
