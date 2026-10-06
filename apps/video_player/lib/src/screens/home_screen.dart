import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../library/private_vault.dart';
import '../library/video_library.dart';
import '../party/join_screen.dart';
import '../player/play_item.dart';
import '../player/player_screen.dart';
import '../player/system_channel.dart';
import '../settings.dart';
import '../widgets/video_thumb.dart';
import 'folder_screen.dart';
import 'network_dialog.dart';
import 'private_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings, required this.vault});

  final Settings settings;
  final PrivateVault vault;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final library = VideoLibrary.instance;
  Settings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    library.start();
    SystemChannel.instance.onOpenUri = (uri) {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      openPlayer(context, settings, [PlayItem.fromExternal(uri)]);
    };
    SystemChannel.instance.takeOpenedUri();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Folders' : 'Recent'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => SearchScreen(settings: settings, vault: widget.vault))),
          ),
          IconButton(
            tooltip: 'Watch together',
            icon: const Icon(Icons.groups_rounded),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => JoinPartyScreen(settings: settings))),
          ),
          IconButton(
            tooltip: 'Play a link',
            icon: const Icon(Icons.link_rounded),
            onPressed: () => showNetworkDialog(context, settings),
          ),
          IconButton(
            tooltip: 'Private folder',
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: () => openPrivateFolder(context, settings, widget.vault),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => SettingsScreen(settings: settings))),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([library, settings]),
            builder: (context, _) =>
                _tab == 0 ? _folders(context) : _recent(context),
          ),
        ),
        const BannerAdSlot(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: 64,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: 'Folders'),
          NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history_toggle_off_rounded),
              label: 'Recent'),
        ],
      ),
    );
  }

  // Folders tab ---------------------------------------------------------------

  Widget _folders(BuildContext context) {
    switch (library.state) {
      case LibraryState.loading:
        return const Center(child: CircularProgressIndicator());
      case LibraryState.noPermission:
        return _PermissionView(onAllow: () => library.start(), onSettings: library.openSettings);
      case LibraryState.ready:
        break;
    }
    final hidden = settings.hiddenFolders;
    final folders = VideoLibrary.sortFolders(
        library.folders.where((f) => !hidden.contains(f.id)).toList(),
        settings.folderSort);
    final resume = settings.recents
        .where((r) => r.position > Duration.zero && r.duration > Duration.zero)
        .firstOrNull;
    return RefreshIndicator(
      onRefresh: library.reload,
      child: CustomScrollView(slivers: [
        if (resume != null)
          SliverToBoxAdapter(child: _ContinueCard(item: resume, settings: settings)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(children: [
              Text('${library.all.length} videos in ${folders.length} folders',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const Spacer(),
              PopupMenuButton<FolderSort>(
                tooltip: 'Sort folders',
                icon: const Icon(Icons.sort_rounded),
                initialValue: settings.folderSort,
                onSelected: settings.setFolderSort,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: FolderSort.name, child: Text('Name')),
                  PopupMenuItem(value: FolderSort.count, child: Text('Most videos')),
                  PopupMenuItem(value: FolderSort.date, child: Text('Recently added')),
                ],
              ),
            ]),
          ),
        ),
        if (library.limitedAccess)
          SliverToBoxAdapter(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Showing only the videos you picked'),
              subtitle: const Text('Tap to allow all videos'),
              onTap: library.openSettings,
            ),
          ),
        if (folders.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _Empty(icon: Icons.video_library_outlined, text: 'No videos on this phone yet'),
          ),
        SliverList.builder(
          itemCount: folders.length,
          itemBuilder: (context, i) => _FolderTile(
            folder: folders[i],
            onLongPress: () => _folderActions(context, folders[i]),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => FolderScreen(
                        folderId: folders[i].id, settings: settings, vault: widget.vault))),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ]),
    );
  }

  void _folderActions(BuildContext context, VideoFolder folder) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: Text('Hide "${folder.name}"'),
            subtitle: const Text('Show it again from Settings'),
            onTap: () {
              Navigator.pop(ctx);
              settings.setFolderHidden(folder.id, true);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${folder.name} hidden'),
                action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () => settings.setFolderHidden(folder.id, false)),
              ));
            },
          ),
        ]),
      ),
    );
  }

  // Recent tab ----------------------------------------------------------------

  Widget _recent(BuildContext context) {
    final items = settings.recents;
    if (items.isEmpty) {
      return const _Empty(icon: Icons.history_rounded, text: 'Videos you play show up here');
    }
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
        child: Row(children: [
          Text('${items.length} played',
              style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          TextButton(onPressed: settings.clearRecents, child: const Text('Clear all')),
        ]),
      ),
      for (final r in items)
        Dismissible(
          key: ValueKey(r.key),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Icon(Icons.delete_outline_rounded),
          ),
          onDismissed: (_) => settings.removeRecent(r.key),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            leading: r.isNetwork
                ? const _LinkThumb()
                : VideoThumb(
                    assetId: r.assetId,
                    width: 96,
                    height: 54,
                    radius: 8,
                    progress: r.duration > Duration.zero
                        ? r.position.inMilliseconds / r.duration.inMilliseconds
                        : 0,
                  ),
            title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              if (r.position > Duration.zero && r.duration > Duration.zero)
                '${formatDuration(r.position)} / ${formatDuration(r.duration)}'
              else if (r.duration > Duration.zero)
                formatDuration(r.duration),
              _ago(r.playedAt),
            ].join('  ·  ')),
            onTap: () => openPlayer(context, settings, [PlayItem.fromRecent(r)]),
          ),
        ),
    ]);
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${t.day}/${t.month}/${t.year}';
}

class _LinkThumb extends StatelessWidget {
  const _LinkThumb();

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        height: 54,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.link_rounded),
      );
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.settings});

  final RecentItem item;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = item.position.inMilliseconds / item.duration.inMilliseconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPlayer(context, settings, [PlayItem.fromRecent(item)]),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Stack(alignment: Alignment.center, children: [
                item.isNetwork
                    ? const _LinkThumb()
                    : VideoThumb(
                        assetId: item.assetId, width: 112, height: 63, progress: progress),
                Container(
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
              ]),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Continue watching',
                      style: TextStyle(
                          color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${formatDuration(item.duration - item.position)} left',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.onTap, this.onLongPress});

  final VideoFolder folder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = folder.videos.length;
    final size = formatSize(folder.totalSize);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          SizedBox(
            width: 96,
            height: 64,
            child: Stack(children: [
              // Two stacked cards hint that this is a folder.
              Positioned(
                left: 8,
                right: 8,
                top: 0,
                height: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Positioned.fill(
                top: 6,
                child: VideoThumb(
                    assetId: folder.videos.first.id, width: 96, height: 58, radius: 10),
              ),
              Positioned(
                left: 6,
                bottom: 5,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: scheme.primary, borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.folder_rounded, size: 14, color: Colors.white),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                  [
                    '$n video${n == 1 ? '' : 's'}',
                    if (size.isNotEmpty) size,
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.onAllow, required this.onSettings});

  final VoidCallback onAllow;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(Icons.video_library_rounded, size: 48, color: scheme.primary),
          ),
          const SizedBox(height: 20),
          Text('Find your videos',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Allow access to videos so the app can list them by folder. '
            'Nothing leaves your phone.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAllow,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Allow access'),
          ),
          TextButton(onPressed: onSettings, child: const Text('Open app settings')),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: c.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text(text, style: TextStyle(color: c)),
      ]),
    );
  }
}
