import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';

import '../doc_store.dart';
import '../ui_helpers.dart';
import 'tools_screen.dart';

/// Saves a copy of a PDF where the user picks (Downloads, Documents, SD
/// card, Drive...) through Android's own "Save as" screen, so no storage
/// permission is needed.
Future<void> saveToPhone(BuildContext context, String name, Uint8List bytes,
    {String mime = 'application/pdf', String ext = 'pdf'}) async {
  try {
    final uri = await FilePicker.saveFile(
        fileName: '${DocStore.sanitize(name)}.$ext', bytes: bytes, mimeType: mime);
    if (uri != null && context.mounted) toast(context, 'Saved to your phone');
  } catch (e) {
    if (context.mounted) toast(context, 'Could not save: $e');
  }
}

/// Opens a PDF inside the app: zoom, scroll, print and share, plus the
/// tools for this document.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.doc});
  final SavedDoc doc;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final Future<Uint8List> _bytes = widget.doc.file.readAsBytes();

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    return Scaffold(
      bottomNavigationBar: const BannerAdSlot(),
      appBar: AppBar(
        title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit, sign, convert',
            icon: const Icon(Icons.auto_fix_high_outlined),
            onPressed: () async {
              final b = await _bytes;
              if (context.mounted) await showToolsFor(context, PickedPdf(d.name, b));
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final b = await _bytes;
              if (!context.mounted) return;
              switch (v) {
                case 'save':
                  await saveToPhone(context, d.name, b);
                case 'print':
                  await Printing.layoutPdf(onLayout: (_) async => b, name: d.name);
                case 'open':
                  await OpenFilex.open(d.file.path, type: 'application/pdf');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'save', child: Text('Save to phone')),
              PopupMenuItem(value: 'print', child: Text('Print')),
              PopupMenuItem(value: 'open', child: Text('Open in another app')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return PdfPreview(
            build: (_) async => snap.data!,
            pdfFileName: '${d.name}.pdf',
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            maxPageWidth: 900,
            onError: (_, e) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    'This PDF can\'t be shown here (it may be locked). Use Unlock PDF in Tools, or open it in another app.',
                    textAlign: TextAlign.center),
              ),
            ),
          );
        },
      ),
    );
  }
}
