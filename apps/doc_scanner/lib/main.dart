import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'doc_store.dart';
import 'review_screen.dart';
import 'scanner.dart';
import 'screens/text_screen.dart';
import 'screens/tools_screen.dart';
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

  @override
  void initState() {
    super.initState();
    docsChanged.addListener(_reload);
  }

  @override
  void dispose() {
    docsChanged.removeListener(_reload);
    super.dispose();
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

  Future<void> _scanMenu() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        Widget item(String v, IconData i, String t, String s) => ListTile(
            leading: Icon(i), title: Text(t), subtitle: Text(s),
            onTap: () => Navigator.pop(c, v));
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              item('doc', Icons.document_scanner_outlined, 'Document',
                  'Auto edge detection, crop and cleanup'),
              item('photo', Icons.photo_camera_outlined, 'Photo',
                  'Take pictures with the camera'),
              item('id', Icons.badge_outlined, 'ID card',
                  'Front and back on one page'),
              item('card', Icons.contact_mail_outlined, 'Business card',
                  'Save the contact details'),
              item('book', Icons.menu_book_outlined, 'Book or notes',
                  'Many pages in one go'),
              item('gallery', Icons.photo_library_outlined, 'Import photos',
                  'Images from your gallery'),
              item('pdf', Icons.upload_file, 'Import PDF',
                  'Add a PDF from your phone'),
            ]),
          ),
        );
      },
    );
    if (pick == null || !mounted) return;
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
        if (all.isEmpty) return const _Empty();
        _loadText(all);
        final q = _query.toLowerCase().trim();
        final docs = all
            .where((d) =>
                d.name.toLowerCase().contains(q) ||
                (q.isNotEmpty && (_text[d.file.path] ?? '').contains(q)))
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                    leading: const Icon(Icons.picture_as_pdf, size: 36),
                    title: Text(d.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(textHit
                        ? 'Text match · ${formatBytes(d.bytes)}'
                        : '${MaterialLocalizations.of(context).formatMediumDate(d.modified)} · ${formatBytes(d.bytes)}'),
                    onTap: () => OpenFilex.open(d.file.path,
                        type: 'application/pdf'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        switch (v) {
                          case 'share':
                            _share(d.file.path);
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
              onPressed: _scanMenu,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan'),
            )
          : null,
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
              'Tap Scan to capture documents, ID cards, business cards or photos. Edges are found automatically, text is recognized, and everything stays on your phone. The Tools tab has merge, split, compress, sign, compare and more.',
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
