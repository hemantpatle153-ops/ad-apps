import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Small in-memory cache so scrolling back up doesn't reload thumbnails.
class _ThumbCache {
  static final _map = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> get(String id) {
    final hit = _map.remove(id);
    if (hit != null) return _map[id] = hit;
    final f = AssetEntity(id: id, typeInt: AssetType.video.index, width: 0, height: 0)
        .thumbnailDataWithSize(const ThumbnailSize(320, 180), quality: 80)
        .catchError((_) => null);
    _map[id] = f;
    if (_map.length > 400) _map.remove(_map.keys.first);
    return f;
  }
}

/// Video thumbnail with rounded corners, or a film icon placeholder.
class VideoThumb extends StatelessWidget {
  const VideoThumb({
    super.key,
    required this.assetId,
    this.width = 128,
    this.height = 72,
    this.radius = 10,
    this.badge,
    this.progress = 0,
  });

  final String? assetId;
  final double width, height, radius;

  /// Text in the bottom-right corner, usually the duration.
  final String? badge;

  /// 0..1 watched fraction, drawn as a bar along the bottom.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.movie_rounded, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          if (assetId == null)
            placeholder
          else
            FutureBuilder<Uint8List?>(
              future: _ThumbCache.get(assetId!),
              builder: (context, snap) {
                final bytes = snap.data;
                if (bytes == null) return placeholder;
                return Image.memory(bytes,
                    fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);
              },
            ),
          if (badge != null && badge!.isNotEmpty)
            Positioned(
              right: 5,
              bottom: progress > 0 ? 8 : 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(badge!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ),
          if (progress > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: scheme.primary,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
              ),
            ),
        ]),
      ),
    );
  }
}
