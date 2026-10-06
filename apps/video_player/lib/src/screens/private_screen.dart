import 'package:flutter/material.dart';

import '../format.dart';
import '../library/private_vault.dart';
import '../player/play_item.dart';
import '../player/player_screen.dart';
import '../settings.dart';
import '../widgets/pin_pad.dart';

/// Asks for the PIN (or sets one up the first time), then opens the folder.
Future<void> openPrivateFolder(
    BuildContext context, Settings settings, PrivateVault vault) async {
  final nav = Navigator.of(context);
  if (!vault.hasPin) {
    final ok = await nav.push<bool>(
        MaterialPageRoute(builder: (_) => PinSetupScreen(vault: vault)));
    if (ok != true) return;
  } else {
    final ok = await nav.push<bool>(
        MaterialPageRoute(builder: (_) => _PinCheckScreen(vault: vault)));
    if (ok != true) return;
  }
  await nav.push<void>(MaterialPageRoute(
      builder: (_) => PrivateScreen(settings: settings, vault: vault)));
}

/// Choose and confirm a 4-digit PIN. Pops true when set.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, required this.vault});

  final PrivateVault vault;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String? _first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Private folder')),
      body: Center(
        child: SingleChildScrollView(
          child: PinPad(
            key: ValueKey(_first),
            title: _first == null ? 'Create a PIN' : 'Enter it again',
            subtitle: _first == null
                ? 'Videos you move here are hidden from the gallery\n'
                    'and other apps. Don\'t forget it: there is no way\n'
                    'to recover the PIN.'
                : null,
            onComplete: (pin) {
              if (_first == null) {
                setState(() => _first = pin);
                return true;
              }
              if (pin != _first) {
                setState(() => _first = null);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PINs didn\'t match, try again')));
                return false;
              }
              widget.vault.setPin(pin);
              Navigator.pop(context, true);
              return true;
            },
          ),
        ),
      ),
    );
  }
}

class _PinCheckScreen extends StatelessWidget {
  const _PinCheckScreen({required this.vault});

  final PrivateVault vault;

  Future<void> _forgot(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot PIN?'),
        content: const Text(
            'The PIN can\'t be recovered. You can reset it, but every video in '
            'the private folder will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete and reset')),
        ],
      ),
    );
    if (ok == true) {
      await vault.reset();
      if (context.mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Private folder')),
      body: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            PinPad(
              title: 'Enter PIN',
              onComplete: (pin) {
                if (!vault.checkPin(pin)) return false;
                Navigator.pop(context, true);
                return true;
              },
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => _forgot(context), child: const Text('Forgot PIN?')),
          ]),
        ),
      ),
    );
  }
}

/// The unlocked private folder. No banner ad here.
class PrivateScreen extends StatefulWidget {
  const PrivateScreen({super.key, required this.settings, required this.vault});

  final Settings settings;
  final PrivateVault vault;

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  @override
  void initState() {
    super.initState();
    widget.vault.load();
  }

  Future<void> _actions(PrivateVideo v) async {
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.lock_open_rounded),
            title: const Text('Move back to gallery'),
            subtitle: Text(v.originalFolder),
            onTap: () => Navigator.pop(ctx, 'unhide'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded),
            title: const Text('Delete forever'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (action == 'unhide') {
      final ok = await widget.vault.unhide(v);
      messenger.showSnackBar(
          SnackBar(content: Text(ok ? 'Moved back to ${v.originalFolder}' : 'Couldn\'t move it')));
    } else if (action == 'delete' && mounted) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete forever?'),
          content: Text(v.title),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (sure == true) await widget.vault.deleteForever(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Private folder')),
      body: ListenableBuilder(
        listenable: widget.vault,
        builder: (context, _) {
          final videos = widget.vault.videos;
          if (videos.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_rounded, size: 56, color: scheme.primary),
                  const SizedBox(height: 12),
                  const Text('Nothing here yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    'Long-press any video and choose "Move to private folder".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
            );
          }
          return ListView.builder(
            itemCount: videos.length,
            itemBuilder: (context, i) {
              final v = videos[i];
              return ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                leading: Container(
                  width: 72,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.lock_rounded, color: scheme.primary),
                ),
                title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatSize(v.size)),
                trailing: IconButton(
                    onPressed: () => _actions(v), icon: const Icon(Icons.more_vert_rounded)),
                onLongPress: () => _actions(v),
                onTap: () => openPlayer(
                  context,
                  widget.settings,
                  [for (final x in videos) PlayItem.fromPrivate(x)],
                  index: i,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
