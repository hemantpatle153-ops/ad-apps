import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'doc_store.dart';
import 'doc_thumb.dart';
import 'review_screen.dart';
import 'scanner.dart';
import 'screens/text_screen.dart';
import 'screens/tools_screen.dart';
import 'screens/viewer_screen.dart';
import 'ui_helpers.dart';

const appPackageName = 'in.onlysoftware.doc_scanner';
const privacyPolicyUrl = 'https://example.com/privacy'; // TODO: your hosted policy

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DocScannerApp());
  // Consent and ads start after the first frame so the app opens instantly.
  AdService.instance.init(AdConfig.fromEnvironment());
}

class DocScannerApp extends StatelessWidget {
  const DocScannerApp({super.key});

  static const _seed = Color(0xFF00897B);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Document Scanner',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(_seed, Brightness.light),
      darkTheme: buildTheme(_seed, Brightness.dark),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<SavedDoc>> _docs = DocStore.instance.list();
  String _query = '';
  int _tab = 0;
  // Recognized text per PDF path, loaded for searching inside documents.
  final Map<String, String> _text = {};

  StreamSubscription<List<SharedMediaFile>>? _shares;

  @override
  void initState() {
    super.initState();
    docsChanged.addListener(_reload);
    // PDFs and photos opened with or shared to Doc Scanner from other apps.
    try {
      _shares = ReceiveSharingIntent.instance.getMediaStream().listen(_received);
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        _received(files);
        ReceiveSharingIntent.instance.reset();
      });
    } catch (_) {
      // Not available (tests, desktop).
    }
  }

  @override
  void dispose() {
    _shares?.cancel();
    docsChanged.removeListener(_reload);
    super.dispose();
  }

  Future<void> _received(List<SharedMediaFile> files) async {
    if (files.isEmpty || !mounted) return;
    final images = <String>[];
    var pdfs = 0;
    for (final f in files) {
      final path = f.path;
      final isPdf = (f.mimeType ?? '').contains('pdf') || path.toLowerCase().endsWith('.pdf');
      if (isPdf) {
        try {
          final name = path.split('/').last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
          await DocStore.instance.savePdf(name, await File(path).readAsBytes());
          pdfs++;
        } catch (_) {}
      } else if (f.type == SharedMediaType.image) {
        images.add(path);
      }
    }
    if (!mounted) return;
    if (pdfs > 0) {
      _reload();
      toast(context, 'Added $pdfs PDF${pdfs == 1 ? '' : 's'}');
    }
    if (images.isNotEmpty) await _start(Future.value(images), title: 'Images');
  }

  void _reload() => setState(() => _docs = DocStore.instance.list());

  Future<void> _loadText(List<SavedDoc> docs) async {
    var changed = false;
    for (final d in docs) {
      if (_text.containsKey(d.file.path)) continue;
      _text[d.file.path] = (await DocStore.instance.readText(d.file)).toLowerCase();
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _start(Future<List<String>> pagesFuture, {String? title}) async {
    final pages = await pagesFuture;
    if (pages.isEmpty || !mounted) return;
    final saved = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => ReviewScreen(pages: pages, title: title)),
    );
    _reload();
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('PDF saved'),
      action: SnackBarAction(
          label: 'Share', onPressed: () => _share(saved.path)),
    ));
    // Natural break: a document was just finished.
    AdService.instance.maybeShowInterstitial();
  }

  void _share(String path) => SharePlus.instance
      .share(ShareParams(files: [XFile(path, mimeType: 'application/pdf')]));

  Future<void> _runScan(String pick) async {
    switch (pick) {
      case 'doc':
        await _start(scanPages(context));
      case 'book':
        await _start(scanPages(context, pageLimit: 100), title: 'Notes');
      case 'photo':
        await _start(takePhotos(context), title: 'Photos');
      case 'gallery':
        await _start(pickFromGallery(), title: 'Images');
      case 'id':
        await runTool(context, Tool.idCard);
      case 'card':
        await runTool(context, Tool.businessCard);
      case 'pdf':
        final files = await pickPdfs(context, multiple: true, keepLocked: true,
            title: 'Import PDFs');
        for (final f in files) {
          await DocStore.instance.savePdf(f.name, f.bytes);
        }
        if (files.isNotEmpty) _reload();
    }
  }

  Future<void> _rename(SavedDoc d) async {
    final name = await askText(context, title: 'Rename', initial: d.name, action: 'Rename');
    if (name == null || name.trim().isEmpty || name.trim() == d.name) return;
    await DocStore.instance.rename(d, name);
    _reload();
  }

  Future<void> _delete(SavedDoc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${d.name}"?'),
        content: const Text('The PDF will be removed from this phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await DocStore.instance.delete(d);
    _reload();
  }

  Future<void> _showText(SavedDoc d) async {
    final saved = await DocStore.instance.readText(d.file);
    if (!mounted) return;
    if (saved.trim().isNotEmpty) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TextScreen(name: d.name, pages: saved.split('\n\n'))));
      return;
    }
    final bytes = await d.file.readAsBytes();
    if (!mounted) return;
    await runTool(context, Tool.extractText, preset: PickedPdf(d.name, bytes));
  }

  Widget _documents() {
    return FutureBuilder<List<SavedDoc>>(
      future: _docs,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data!;
        if (all.isEmpty) {
          return Column(children: [_QuickActions(onPick: _runScan), const Expanded(child: _Empty())]);
        }
        _loadText(all);
        final q = _query.toLowerCase().trim();
        final docs = all
            .where((d) =>
                d.name.toLowerCase().contains(q) ||
                (q.isNotEmpty && (_text[d.file.path] ?? '').contains(q)))
            .toList();
        return Column(
          children: [
            _QuickActions(onPick: _runScan),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: SearchBar(
                hintText: 'Search names and text in documents',
                leading: const Icon(Icons.search),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final textHit = q.isNotEmpty && !d.name.toLowerCase().contains(q);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: DocThumb(doc: d),
                    title: Text(d.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(textHit
                        ? 'Text match · ${formatBytes(d.bytes)}'
                        : '${MaterialLocalizations.of(context).formatMediumDate(d.modified)} · ${formatBytes(d.bytes)}'),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ViewerScreen(doc: d))),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        switch (v) {
                          case 'share':
                            _share(d.file.path);
                          case 'save':
                            final bytes = await d.file.readAsBytes();
                            if (!context.mounted) return;
                            await saveToPhone(context, d.name, bytes);
                          case 'open':
                            await OpenFilex.open(d.file.path, type: 'application/pdf');
                          case 'tools':
                            final bytes = await d.file.readAsBytes();
                            if (!context.mounted) return;
                            await showToolsFor(context, PickedPdf(d.name, bytes));
                          case 'text':
                            await _showText(d);
                          case 'rename':
                            await _rename(d);
                          case 'delete':
                            await _delete(d);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'share', child: Text('Share')),
                        PopupMenuItem(value: 'save', child: Text('Save to phone')),
                        PopupMenuItem(value: 'open', child: Text('Open in another app')),
                        PopupMenuItem(value: 'tools', child: Text('Edit, sign, convert…')),
                        PopupMenuItem(value: 'text', child: Text('Copy text')),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BannerAdSlot(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Documents'),
              NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: 'Tools'),
            ],
          ),
        ],
      ),
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Document Scanner' : 'PDF tools'),
        actions: [
          IconButton(
            tooltip: 'Import photos',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => _start(pickFromGallery(), title: 'Images'),
          ),
          const _Menu(),
        ],
      ),
      body: _tab == 0 ? _documents() : const ToolsScreen(),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _runScan('doc'),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan'),
            )
          : null,
    );
  }
}

/// One-tap shortcuts to every way of adding a document.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onPick});
  final Future<void> Function(String) onPick;

  static const _items = [
    ('doc', Icons.document_scanner_outlined, 'Scan'),
    ('id', Icons.badge_outlined, 'ID card'),
    ('card', Icons.contact_mail_outlined, 'Business\ncard'),
    ('book', Icons.menu_book_outlined, 'Book'),
    ('photo', Icons.photo_camera_outlined, 'Photo'),
    ('gallery', Icons.photo_library_outlined, 'Import\nphotos'),
    ('pdf', Icons.upload_file, 'Import\nPDF'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          for (final (id, icon, label) in _items)
            SizedBox(
              width: 76,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onPick(id),
                child: Column(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: id == 'doc' ? scheme.primary : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon,
                        color: id == 'doc' ? scheme.onPrimary : scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.labelSmall),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.document_scanner_outlined,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('No documents yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text(
              'Tap Scan and point the camera at a page. Edges are found and captured automatically, shadows are cleaned up, and text is recognized, all on your phone. The Tools tab has merge, split, compress, sign, compare and more.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AdService.instance.privacyOptionsRequired(),
      builder: (context, snap) => PopupMenuButton<VoidCallback>(
        onSelected: (fn) => fn(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () => openStorePage(appPackageName),
            child: const Text('Rate this app'),
          ),
          PopupMenuItem(
            value: () => openLink(privacyPolicyUrl),
            child: const Text('Privacy policy'),
          ),
          if (snap.data == true)
            PopupMenuItem(
              value: AdService.instance.showPrivacyOptions,
              child: const Text('Ad privacy choices'),
            ),
        ],
      ),
    );
  }
}
