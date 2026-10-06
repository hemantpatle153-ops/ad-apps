import 'package:flutter/material.dart';

import '../format.dart';
import '../library/private_vault.dart';
import '../library/video_library.dart';
import '../player/play_item.dart';
import '../player/player_screen.dart';
import '../settings.dart';
import 'private_screen.dart';

/// Long-press menu for a video: play, info, move to private, delete.
Future<void> showVideoActions(
  BuildContext context, {
  required VideoEntry video,
  required Settings settings,
  required PrivateVault vault,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.play_arrow_rounded),
          title: const Text('Play'),
          onTap: () {
            Navigator.pop(ctx);
            openPlayer(context, settings, [PlayItem.fromEntry(video)]);
          },
        ),
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('Properties'),
          onTap: () {
            Navigator.pop(ctx);
            _showInfo(context, video);
          },
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline_rounded),
          title: const Text('Move to private folder'),
          onTap: () async {
            Navigator.pop(ctx);
            await moveToPrivate(context, video, vault);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: const Text('Delete'),
          onTap: () async {
            Navigator.pop(ctx);
            final done = await VideoLibrary.instance.delete([video.id]);
            if (done.isNotEmpty) settings.removeRecent(video.id);
          },
        ),
      ]),
    ),
  );
}

Future<void> moveToPrivate(BuildContext context, VideoEntry video, PrivateVault vault) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!vault.hasPin) {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PinSetupScreen(vault: vault)));
    if (ok != true) return;
  }
  messenger.showSnackBar(const SnackBar(content: Text('Moving to private folder…')));
  final ok = await vault.hide(video);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(ok ? 'Moved to private folder' : 'Not moved')));
}

void _showInfo(BuildContext context, VideoEntry v) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Properties'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (k, val) in [
            ('Name', v.title),
            ('Folder', v.folder),
            ('Duration', formatDuration(v.duration)),
            ('Size', formatSize(v.size)),
            ('Resolution', '${v.width} × ${v.height}'),
            ('Modified', v.modified.toString().split('.').first),
            if (v.path != null) ('Location', v.path!),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$k\n', style: Theme.of(ctx).textTheme.labelMedium),
                TextSpan(text: val),
              ])),
            ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}
