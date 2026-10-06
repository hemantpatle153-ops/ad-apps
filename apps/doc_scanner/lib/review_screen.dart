import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'doc_store.dart';
import 'image_filters.dart';
import 'jobs.dart';
import 'ocr.dart';
import 'scanner.dart';
import 'ui_helpers.dart';

/// A page photo plus the look the user picked for it.
class ScanPage {
  ScanPage(this.path);
  final String path;
  PageFilter filter = PageFilter.original;
  int turns = 0;
}

/// Reorder, edit (filters, rotate), remove or add pages, then save them as
/// one searchable PDF or as JPG images.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.pages, this.title});
  final List<String> pages;
  final String? title;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final List<ScanPage> _pages = [for (final p in widget.pages) ScanPage(p)];
  late final TextEditingController _name = TextEditingController(
      text: '${widget.title ?? 'Scan'} ${stamp(DateTime.now())}');
  PageSize _size = PageSize.a4;
  bool _ocr = true;
  String? _progress;

  static String stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}.${two(d.minute)}';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addMore() async {
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan document'),
              onTap: () => Navigator.pop(c, 'scan')),
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(c, 'photo')),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('From gallery'),
              onTap: () => Navigator.pop(c, 'gallery')),
        ]),
      ),
    );
    if (how == null || !mounted) return;
    final Future<List<String>> pick = switch (how) {
      'scan' => scanPages(context),
      'photo' => takePhotos(context),
      _ => pickFromGallery(),
    };
    final more = await pick;
    if (more.isNotEmpty) {
      setState(() => _pages.addAll([for (final p in more) ScanPage(p)]));
    }
  }

  /// Applies each page's filter and rotation; returns JPEG bytes.
  Future<List<Uint8List>> _render() async {
    final out = <Uint8List>[];
    for (var i = 0; i < _pages.length; i++) {
      setState(() => _progress = 'Preparing page ${i + 1} of ${_pages.length}');
      final p = _pages[i];
      final raw = await File(p.path).readAsBytes();
      final filter = p.filter, turns = p.turns;
      out.add(await bg(processJob, (raw, filter, turns, 2400, 88)));
    }
    return out;
  }

  Future<void> _save() async {
    if (_pages.isEmpty) return;
    try {
      final images = await _render();
      List<PageText?>? text;
      if (_ocr) {
        text = [];
        for (var i = 0; i < images.length; i++) {
          setState(() =>
              _progress = 'Reading text on page ${i + 1} of ${images.length}');
          try {
            text.add(await Ocr.readBytes(images[i]));
          } catch (_) {
            text.add(null); // OCR is a bonus; never block saving.
          }
        }
      }
      setState(() => _progress = 'Saving PDF');
      final pdf = await DocStore.buildPdf(images, _size, text: text);
      final file = await DocStore.instance.savePdf(_name.text, pdf);
      if (text != null) {
        await DocStore.instance.saveText(
            file, text.map((t) => t?.plain ?? '').join('\n\n'));
      }
      if (!mounted) return;
      Navigator.pop(context, file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress = null);
      toast(context, 'Could not save the PDF: $e');
    }
  }

  Future<void> _saveJpg() async {
    try {
      final images = await _render();
      final files = <File>[];
      for (var i = 0; i < images.length; i++) {
        files.add(await DocStore.instance
            .saveExport('${_name.text} ${i + 1}.jpg', images[i]));
      }
      setState(() => _progress = null);
      shareFiles(files, mime: 'image/jpeg');
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress = null);
      toast(context, 'Could not export images: $e');
    }
  }

  Future<void> _edit(int i) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditPageScreen(page: _pages[i], number: i + 1)),
    );
    if (changed == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    return Scaffold(
      bottomNavigationBar: const BannerAdSlot(),
      appBar: AppBar(
        title: Text('${_pages.length} page${_pages.length == 1 ? '' : 's'}'),
        actions: [
          IconButton(
            tooltip: 'Add pages',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: busy ? null : _addMore,
          ),
          PopupMenuButton<String>(
            enabled: !busy && _pages.isNotEmpty,
            onSelected: (v) {
              if (v == 'jpg') _saveJpg();
              if (v == 'all') {
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (c) => SafeArea(
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final f in PageFilter.values)
                        ActionChip(
                          label: Text(f.label),
                          onPressed: () {
                            setState(() {
                              for (final p in _pages) {
                                p.filter = f;
                              }
                            });
                            Navigator.pop(c);
                          },
                        ),
                    ]),
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Filter for all pages')),
              PopupMenuItem(value: 'jpg', child: Text('Save as JPG images')),
            ],
          ),
        ],
      ),
      body: busy
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_progress!),
              ]),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'File name',
                      border: OutlineInputBorder(),
                      suffixText: '.pdf',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SegmentedButton<PageSize>(
                    segments: [
                      for (final s in PageSize.values)
                        ButtonSegment(value: s, label: Text(s.label)),
                    ],
                    selected: {_size},
                    onSelectionChanged: (v) => setState(() => _size = v.first),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  value: _ocr,
                  onChanged: (v) => setState(() => _ocr = v),
                  title: const Text('Recognize text (OCR)'),
                  subtitle: const Text(
                      'Makes the PDF searchable and its text copyable'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                      'Tap a page to edit it. Long-press and drag to reorder.'),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _pages.length,
                    onReorderItem: (from, to) => setState(
                        () => _pages.insert(to, _pages.removeAt(from))),
                    itemBuilder: (_, i) {
                      final p = _pages[i];
                      return Card(
                        key: ObjectKey(p),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(8),
                          leading: SizedBox(
                            width: 56,
                            height: 72,
                            child: RotatedBox(
                              quarterTurns: p.turns,
                              child: Image.file(File(p.path),
                                  fit: BoxFit.cover, cacheWidth: 160),
                            ),
                          ),
                          title: Text('Page ${i + 1}'),
                          subtitle: Text(p.filter.label),
                          trailing: IconButton(
                            tooltip: 'Remove page',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _pages.removeAt(i)),
                          ),
                          onTap: () => _edit(i),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: busy || _pages.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _save,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Save PDF'),
            ),
    );
  }
}

/// Filters and rotation for one page, with a live preview.
class EditPageScreen extends StatefulWidget {
  const EditPageScreen({super.key, required this.page, required this.number});
  final ScanPage page;
  final int number;

  @override
  State<EditPageScreen> createState() => _EditPageScreenState();
}

class _EditPageScreenState extends State<EditPageScreen> {
  late PageFilter _filter = widget.page.filter;
  late int _turns = widget.page.turns;
  Uint8List? _raw;
  Uint8List? _preview;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    File(widget.page.path).readAsBytes().then((b) {
      _raw = b;
      _refresh();
    });
  }

  Future<void> _refresh() async {
    final raw = _raw;
    if (raw == null) return;
    final job = ++_job;
    final filter = _filter;
    // Rotation is shown with RotatedBox, so the preview only needs the filter.
    final out = await bg(processJob, (raw, filter, 0, 1000, 80));
    if (mounted && job == _job) setState(() => _preview = out);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Page ${widget.number}'),
        actions: [
          TextButton(
            onPressed: () {
              widget.page
                ..filter = _filter
                ..turns = _turns;
              Navigator.pop(context, true);
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _preview == null
                ? const Center(child: CircularProgressIndicator())
                : InteractiveViewer(
                    child: Center(
                      child: RotatedBox(
                          quarterTurns: _turns, child: Image.memory(_preview!)),
                    ),
                  ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final f in PageFilter.values)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: f == _filter,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _refresh();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _turns = (_turns + 3) % 4),
                icon: const Icon(Icons.rotate_left),
                label: const Text('Left'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _turns = (_turns + 1) % 4),
                icon: const Icon(Icons.rotate_right),
                label: const Text('Right'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
