import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../pdf_render.dart';
import '../pdf_tools.dart';

/// Reorder, rotate, duplicate and delete pages. Returns the new page list.
class OrganizeScreen extends StatefulWidget {
  const OrganizeScreen({super.key, required this.pdf, required this.name});
  final Uint8List pdf;
  final String name;

  @override
  State<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _Item {
  _Item(this.ref);
  PageRef ref;
}

class _OrganizeScreenState extends State<OrganizeScreen> {
  List<Uint8List>? _thumbs;
  final _items = <_Item>[];

  @override
  void initState() {
    super.initState();
    PdfRender.pngs(widget.pdf, dpi: 36).then((t) {
      if (!mounted) return;
      setState(() {
        _thumbs = t;
        _items.addAll([for (var i = 0; i < t.length; i++) _Item(PageRef(i))]);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Organize ${widget.name}'),
        actions: [
          TextButton(
            onPressed: _items.isEmpty
                ? null
                : () => Navigator.pop(context, [for (final i in _items) i.ref]),
            child: const Text('Save'),
          ),
        ],
      ),
      body: _thumbs == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Long-press and drag a page to move it.'),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _items.length,
                  onReorderItem: (from, to) =>
                      setState(() => _items.insert(to, _items.removeAt(from))),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    return Card(
                      key: ObjectKey(it),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(children: [
                          SizedBox(
                            width: 72,
                            height: 96,
                            child: RotatedBox(
                              quarterTurns: it.ref.quarterTurns,
                              child: Image.memory(_thumbs![it.ref.index]),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Page ${i + 1}\n(was ${it.ref.index + 1})'),
                          ),
                          IconButton(
                            tooltip: 'Rotate',
                            icon: const Icon(Icons.rotate_right),
                            onPressed: () => setState(() => it.ref = it.ref.turned(1)),
                          ),
                          IconButton(
                            tooltip: 'Duplicate',
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () => setState(
                                () => _items.insert(i + 1, _Item(it.ref))),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _items.removeAt(i)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
    );
  }
}
