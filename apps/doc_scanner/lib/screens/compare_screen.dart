import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../ocr.dart';
import '../pdf_render.dart';
import '../scanner.dart';
import '../text_diff.dart';
import '../ui_helpers.dart';

/// One side of a comparison: a PDF or freshly taken photos.
class _Side {
  _Side(this.name, this.texts, this.previews);
  final String name;
  final List<String> texts;
  final List<Uint8List> previews;
  String get text => texts.join('\n');
}

/// Compare two documents: word-by-word changes, plus pages side by side.
/// Either side can be a saved PDF, a file on the phone, or new photos.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final _sides = <_Side?>[null, null];
  DiffSummary? _diff;

  Future<void> _choose(int which) async {
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Choose a PDF'),
              onTap: () => Navigator.pop(c, 'pdf')),
          ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan pages'),
              onTap: () => Navigator.pop(c, 'scan')),
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photos'),
              onTap: () => Navigator.pop(c, 'photo')),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('From gallery'),
              onTap: () => Navigator.pop(c, 'gallery')),
        ]),
      ),
    );
    if (how == null || !mounted) return;
    _Side? side;
    if (how == 'pdf') {
      final picked = await pickPdfs(context, title: 'Document ${which + 1}');
      if (picked.isEmpty || !mounted) return;
      final p = picked.first;
      side = await busy(context, 'Reading "${p.name}"', () async {
        final texts = await PdfRender.textWithOcr(p.bytes);
        final previews = await PdfRender.pngs(p.bytes, dpi: 60);
        return _Side(p.name, texts, previews);
      });
    } else {
      final Future<List<String>> pick = switch (how) {
        'scan' => scanPages(context),
        'photo' => takePhotos(context),
        _ => pickFromGallery(),
      };
      final paths = await pick;
      if (paths.isEmpty || !mounted) return;
      side = await busy(context, 'Reading text from photos', () async {
        final texts = <String>[];
        final previews = <Uint8List>[];
        for (final p in paths) {
          texts.add((await Ocr.readFile(p)).plain);
          previews.add(await File(p).readAsBytes());
        }
        return _Side('Photos (${paths.length})', texts, previews);
      });
    }
    if (side == null || !mounted) return;
    setState(() {
      _sides[which] = side;
      _diff = null;
    });
    final a = _sides[0], b = _sides[1];
    if (a != null && b != null) {
      final d = await busy(context, 'Comparing', () => bg(_diffJob, (a.text, b.text)));
      if (!mounted) return;
      setState(() => _diff = d);
      AdService.instance.maybeShowInterstitial();
    }
  }

  static DiffSummary _diffJob((String, String) t) => diffWords(t.$1, t.$2);

  Widget _slot(int i) {
    final s = _sides[i];
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: () => _choose(i),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Icon(s == null ? Icons.add_circle_outline : Icons.description_outlined,
                  size: 32),
              const SizedBox(height: 6),
              Text(s?.name ?? 'Document ${i + 1}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
              Text(s == null ? 'Tap to choose' : '${s.texts.length} page(s)',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _diff;
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        bottomNavigationBar: const BannerAdSlot(),
        appBar: AppBar(
          title: const Text('Compare documents'),
          bottom: d == null
              ? null
              : const TabBar(tabs: [Tab(text: 'Changes'), Tab(text: 'Side by side')]),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [_slot(0), _slot(1)]),
          ),
          if (d == null)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Pick two versions of a document (PDFs, scans or photos). Text is read on your phone and every added or removed word is highlighted.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: TabBarView(children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      d.identical
                          ? 'The text is identical.'
                          : '${(d.similarity * 100).round()}% the same · ${d.added} words added · ${d.removed} words removed',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 12, children: [
                      _legend(Colors.green.withValues(alpha: 0.3), 'Only in document 2'),
                      _legend(Colors.red.withValues(alpha: 0.3), 'Only in document 1'),
                    ]),
                    const Divider(),
                    SelectableText.rich(TextSpan(
                      style: TextStyle(color: scheme.onSurface, height: 1.5),
                      children: [
                        for (final p in d.parts)
                          TextSpan(
                            text: '${p.text} ',
                            style: switch (p.op) {
                              DiffOp.same => null,
                              DiffOp.added => TextStyle(
                                  backgroundColor: Colors.green.withValues(alpha: 0.3)),
                              DiffOp.removed => TextStyle(
                                  backgroundColor: Colors.red.withValues(alpha: 0.3),
                                  decoration: TextDecoration.lineThrough),
                            },
                          ),
                      ],
                    )),
                  ],
                ),
                _SideBySide(a: _sides[0]!, b: _sides[1]!),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, color: c),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.a, required this.b});
  final _Side a, b;

  @override
  Widget build(BuildContext context) {
    final n = a.previews.length > b.previews.length ? a.previews.length : b.previews.length;
    Widget cell(_Side s, int i) => Expanded(
          child: i < s.previews.length
              ? InteractiveViewer(child: Image.memory(s.previews[i]))
              : const SizedBox(height: 120, child: Center(child: Text('No page'))),
        );
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: n,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(children: [
          Text('Page ${i + 1}'),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cell(a, i),
            const SizedBox(width: 8),
            cell(b, i),
          ]),
        ]),
      ),
    );
  }
}
