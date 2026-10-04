import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'doc_store.dart';
import 'review_screen.dart';
import 'scanner.dart';

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

  void _reload() => setState(() => _docs = DocStore.instance.list());

  Future<void> _start(Future<List<String>> pagesFuture) async {
    final pages = await pagesFuture;
    if (pages.isEmpty || !mounted) return;
    final saved = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => ReviewScreen(pages: pages)),
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

  Future<void> _rename(SavedDoc d) async {
    final c = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Rename')),
        ],
      ),
    );
    c.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BannerAdSlot(),
      appBar: AppBar(
        title: const Text('Document Scanner'),
        actions: [
          IconButton(
            tooltip: 'Import photos',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => _start(pickFromGallery()),
          ),
          const _Menu(),
        ],
      ),
      body: FutureBuilder<List<SavedDoc>>(
        future: _docs,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          if (all.isEmpty) return const _Empty();
          final q = _query.toLowerCase();
          final docs =
              all.where((d) => d.name.toLowerCase().contains(q)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SearchBar(
                  hintText: 'Search documents',
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
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf, size: 36),
                      title: Text(d.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${MaterialLocalizations.of(context).formatMediumDate(d.modified)} · ${formatBytes(d.bytes)}'),
                      onTap: () => OpenFilex.open(d.file.path,
                          type: 'application/pdf'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          switch (v) {
                            case 'share':
                              _share(d.file.path);
                            case 'rename':
                              _rename(d);
                            case 'delete':
                              _delete(d);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'share', child: Text('Share')),
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _start(scanPages(context)),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
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
              'Tap Scan to photograph receipts, notes or forms. Edges are found automatically and every page is saved into one PDF on your phone.',
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
