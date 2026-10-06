import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../doc_store.dart';
import '../docx_writer.dart';
import '../ui_helpers.dart';

/// Shows recognized or extracted text, ready to copy or export.
class TextScreen extends StatelessWidget {
  const TextScreen({super.key, required this.name, required this.pages});
  final String name;
  final List<String> pages;

  String get _all => pages.map((p) => p.trim()).join('\n\n');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BannerAdSlot(),
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _all));
              toast(context, 'Text copied');
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final f = v == 'docx'
                  ? await DocStore.instance.saveExport('$name.docx', buildDocx(pages))
                  : await DocStore.instance.saveExport('$name.txt', utf8.encode(_all));
              shareFiles([f],
                  mime: v == 'docx'
                      ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                      : 'text/plain');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'txt', child: Text('Share as text file')),
              PopupMenuItem(value: 'docx', child: Text('Share as Word (.docx)')),
            ],
          ),
        ],
      ),
      body: _all.trim().isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No text was found in this document.',
                  textAlign: TextAlign.center),
            ))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pages.length,
              itemBuilder: (_, i) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pages.length > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Page ${i + 1}',
                          style: Theme.of(context).textTheme.labelLarge),
                    ),
                  SelectableText(pages[i].trim()),
                ],
              ),
            ),
    );
  }
}
