import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../library/private_vault.dart';
import '../library/video_library.dart';
import '../player/play_item.dart';
import '../player/player_screen.dart';
import '../settings.dart';
import '../widgets/video_tile.dart';
import 'video_actions.dart';

/// Searches every video on the phone by name.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.settings, required this.vault});

  final Settings settings;
  final PrivateVault vault;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    final results = q.isEmpty
        ? <VideoEntry>[]
        : VideoLibrary.sortVideos(
            VideoLibrary.instance.all.where((v) => v.matches(q)).toList(),
            VideoSort.name,
            false);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search videos',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: q.isNotEmpty && results.isEmpty
              ? const Center(child: Text('No videos match'))
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) => VideoTile(
                    video: results[i],
                    settings: widget.settings,
                    showFolder: true,
                    onTap: () => openPlayer(
                        context, widget.settings, [PlayItem.fromEntry(results[i])]),
                    onMore: () => showVideoActions(context,
                        video: results[i], settings: widget.settings, vault: widget.vault),
                  ),
                ),
        ),
        const BannerAdSlot(),
      ]),
    );
  }
}
