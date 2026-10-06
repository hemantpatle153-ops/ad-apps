import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/play_item.dart';
import '../player/player_screen.dart';
import '../settings.dart';

/// Asks for a stream url (mp4, m3u8, mkv over http) and plays it.
Future<void> showNetworkDialog(BuildContext context, Settings settings) async {
  final controller = TextEditingController();
  final clip = await Clipboard.getData(Clipboard.kTextPlain);
  final pasted = clip?.text?.trim() ?? '';
  if (pasted.startsWith('http')) controller.text = pasted;
  if (!context.mounted) return;
  final url = await showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final u = controller.text.trim();
        if (Uri.tryParse(u)?.hasScheme ?? false) Navigator.pop(ctx, u);
      }

      return AlertDialog(
        title: const Text('Play from a link'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://example.com/video.mp4',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              onSubmitted: (_) => submit(),
            ),
            if (settings.streamHistory.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final u in settings.streamHistory.take(4))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(ctx, u),
                ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('Play')),
        ],
      );
    },
  );
  if (url == null || !context.mounted) return;
  settings.addStream(url);
  await openPlayer(context, settings, [PlayItem.fromUrl(url)]);
}
