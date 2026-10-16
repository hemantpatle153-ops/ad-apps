import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'doc_store.dart';
import 'image_filters.dart';
import 'jobs.dart';
import 'ocr.dart';
import 'scan/capture.dart';
import 'scan/crop_screen.dart';
import 'scanner.dart';
import 'ui_helpers.dart';

/// A page photo plus the look the user picked for it.
class ScanPage {
  ScanPage(this.path)
      : filter = pageSources[path]?.enhance ?? false ? PageFilter.magic : PageFilter.original;
  String path;
  PageFilter filter;
  int turns = 0;

  /// The brightness and contrast sliders, each -100..100.
  int brightness = 0;
  int contrast = 0;

  /// Copies [other]'s look (filter and sliders), not its rotation.
  void copyLook(ScanPage other) {
    filter = other.filter;
    brightness = other.brightness;
    contrast = other.contrast;
  }
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
      final filter = p.filter, turns = p.turns, b = p.brightness, c = p.contrast;
      // 3000 px is about 300 dpi on A4, so small print stays sharp.
      out.add(await bg(renderJob, (raw, filter, turns, 3000, 88, b, c)));
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
    final r = await Navigator.of(context).push<EditResult>(
      MaterialPageRoute(builder: (_) => EditPageScreen(page: _pages[i], number: i + 1)),
    );
    if (r == null || !mounted) return;
    setState(() {
      if (r == EditResult.applyToAll) {
        for (final p in _pages) {
          p.copyLook(_pages[i]);
        }
      }
    });
    if (r == EditResult.applyToAll) toast(context, 'Applied to all ${_pages.length} pages');
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
                                p
                                  ..filter = f
                                  ..brightness = 0
                                  ..contrast = 0;
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

/// How the page editor was closed.
enum EditResult { done, applyToAll }

/// Filters (with previews), brightness and contrast, crop and rotation for
/// one page, with a live preview, like Adobe Scan's page editor.
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
  late double _brightness = widget.page.brightness.toDouble();
  late double _contrast = widget.page.contrast.toDouble();
  bool _adjusting = false;
  Uint8List? _raw;
  Uint8List? _preview;
  List<Uint8List>? _thumbs;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    _load(widget.page.path);
  }

  Future<void> _load(String path) async {
    _raw = await File(path).readAsBytes();
    _refresh();
    final thumbs = await bg(filterPreviewsJob, _raw!);
    if (mounted) setState(() => _thumbs = thumbs);
  }

  Future<void> _crop() async {
    final path = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => CropScreen(pagePath: widget.page.path)));
    if (path == null || !mounted) return;
    widget.page.path = path;
    setState(() => _thumbs = null);
    _load(path);
  }

  Future<void> _refresh() async {
    final raw = _raw;
    if (raw == null) return;
    final job = ++_job;
    final f = _filter, b = _brightness.round(), c = _contrast.round();
    // Rotation is shown with RotatedBox, so the preview only needs the look.
    final out = await bg(renderJob, (raw, f, 0, 1400, 85, b, c));
    if (mounted && job == _job) setState(() => _preview = out);
  }

  void _close(EditResult r) {
    widget.page
      ..filter = _filter
      ..turns = _turns
      ..brightness = _brightness.round()
      ..contrast = _contrast.round();
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Page ${widget.number}'),
        actions: [
          TextButton(
            onPressed: () => _close(EditResult.applyToAll),
            child: const Text('Apply to all'),
          ),
          FilledButton(
            onPressed: () => _close(EditResult.done),
            child: const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: _preview == null
                  ? const Center(child: CircularProgressIndicator())
                  : InteractiveViewer(
                      maxScale: 6,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: RotatedBox(
                              quarterTurns: _turns,
                              child: Image.memory(_preview!, gaplessPlayback: true)),
                        ),
                      ),
                    ),
            ),
          ),
          if (_adjusting) _sliders(),
          SizedBox(
            height: 112,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: PageFilter.values.length,
              itemBuilder: (_, i) {
                final f = PageFilter.values[i];
                final selected = f == _filter;
                final thumb = _thumbs?[i];
                return GestureDetector(
                  onTap: () {
                    setState(() => _filter = f);
                    _refresh();
                  },
                  child: Container(
                    width: 72,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: selected ? scheme.primary : scheme.outlineVariant,
                                width: selected ? 3 : 1),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: thumb == null
                              ? const Center(
                                  child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2)))
                              : Image.memory(thumb, fit: BoxFit.cover, width: 72),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(f.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                              color: selected ? scheme.primary : null)),
                    ]),
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Tool(icon: Icons.crop, label: 'Crop', onTap: _crop),
              _Tool(
                icon: Icons.tune,
                label: 'Adjust',
                selected: _adjusting,
                onTap: () => setState(() => _adjusting = !_adjusting),
              ),
              _Tool(
                icon: Icons.rotate_left,
                label: 'Left',
                onTap: () => setState(() => _turns = (_turns + 3) % 4),
              ),
              _Tool(
                icon: Icons.rotate_right,
                label: 'Right',
                onTap: () => setState(() => _turns = (_turns + 1) % 4),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sliders() {
    Widget row(String label, IconData icon, double value, ValueChanged<double> set) => Row(
          children: [
            const SizedBox(width: 12),
            Icon(icon, size: 20),
            SizedBox(width: 84, child: Text('  $label')),
            Expanded(
              child: Slider(
                min: -100,
                max: 100,
                divisions: 40,
                value: value,
                label: value.round().toString(),
                onChanged: (v) => setState(() => set(v)),
                onChangeEnd: (_) => _refresh(),
              ),
            ),
          ],
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      row('Brightness', Icons.brightness_6_outlined, _brightness, (v) => _brightness = v),
      row('Contrast', Icons.contrast, _contrast, (v) => _contrast = v),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _brightness == 0 && _contrast == 0
              ? null
              : () {
                  setState(() => _brightness = _contrast = 0);
                  _refresh();
                },
          child: const Text('Reset'),
        ),
      ),
    ]);
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap, this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = selected ? Theme.of(context).colorScheme.primary : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: c)),
        ]),
      ),
    );
  }
}
