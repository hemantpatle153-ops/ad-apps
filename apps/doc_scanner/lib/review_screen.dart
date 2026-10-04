import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'doc_store.dart';
import 'scanner.dart';

/// Reorder, remove or add pages, then save them as one PDF.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.pages});
  final List<String> pages;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final List<String> _pages = List.of(widget.pages);
  late final TextEditingController _name = TextEditingController(
      text: 'Scan ${_stamp(DateTime.now())}');
  PageSize _size = PageSize.a4;
  bool _saving = false;

  static String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}.${two(d.minute)}';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addMore() async {
    final more = await scanPages(context);
    if (more.isNotEmpty) setState(() => _pages.addAll(more));
  }

  Future<void> _save() async {
    if (_pages.isEmpty) return;
    setState(() => _saving = true);
    try {
      final images = <Uint8List>[
        for (final p in _pages) await File(p).readAsBytes(),
      ];
      final pdf = await DocStore.buildPdf(images, _size);
      final file = await DocStore.instance.savePdf(_name.text, pdf);
      if (!mounted) return;
      Navigator.pop(context, file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save the PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BannerAdSlot(),
      appBar: AppBar(
        title: Text('${_pages.length} page${_pages.length == 1 ? '' : 's'}'),
        actions: [
          IconButton(
            tooltip: 'Add pages',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: _saving ? null : _addMore,
          ),
        ],
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Long-press and drag a page to reorder it.'),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _pages.length,
                    onReorderItem: (from, to) => setState(
                        () => _pages.insert(to, _pages.removeAt(from))),
                    itemBuilder: (_, i) => Card(
                      key: ValueKey('${_pages[i]}#$i'),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(8),
                        leading: SizedBox(
                          width: 56,
                          height: 72,
                          child: Image.file(File(_pages[i]),
                              fit: BoxFit.cover, cacheWidth: 160),
                        ),
                        title: Text('Page ${i + 1}'),
                        trailing: IconButton(
                          tooltip: 'Remove page',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _pages.removeAt(i)),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: Text('Page ${i + 1}')),
                              body: InteractiveViewer(
                                child: Center(child: Image.file(File(_pages[i]))),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _saving || _pages.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _save,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Save PDF'),
            ),
    );
  }
}
