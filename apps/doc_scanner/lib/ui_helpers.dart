import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'doc_store.dart';
import 'jobs.dart';
import 'pdf_tools.dart';

/// Bumped whenever a PDF is added or changed, so the list reloads.
final docsChanged = ValueNotifier<int>(0);

/// Runs [fn] with [arg] off the UI thread. Pass a top-level or static
/// function (never a closure from a widget, which would drag the widget
/// into the other isolate); if sending still fails it runs here instead.
Future<R> bg<A, R>(R Function(A) fn, A arg) async {
  try {
    return await Isolate.run(() => fn(arg));
  } on ArgumentError catch (e) {
    if (!'$e'.contains('isolate')) rethrow;
    return fn(arg);
  }
}

/// Shows a blocking "working" dialog while [work] runs. Returns null and
/// shows the error if it fails.
Future<T?> busy<T>(BuildContext context, String label, Future<T> Function() work) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(label)),
        ]),
      ),
    ),
  );
  try {
    return await work();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return null;
  } finally {
    nav.pop();
  }
}

String friendlyError(Object e) {
  if (e is PasswordRequired) return 'Wrong password, or the PDF is locked.';
  if (e is FormatException) return e.message;
  if (e is ArgumentError) return '${e.message}';
  return 'Something went wrong: $e';
}

void toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(text)));

void shareFiles(List<File> files, {String? mime}) => SharePlus.instance.share(
    ShareParams(files: [for (final f in files) XFile(f.path, mimeType: mime)]));

/// A PDF chosen for a tool, from the app or from the phone's files.
class PickedPdf {
  PickedPdf(this.name, this.bytes);
  final String name;
  Uint8List bytes;
}

Future<String?> askText(BuildContext context,
    {required String title,
    String initial = '',
    String? hint,
    bool password = false,
    String action = 'OK',
    TextInputType? keyboard}) async {
  final c = TextEditingController(text: initial);
  var hide = password;
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: hide,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: password
                ? IconButton(
                    icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => set(() => hide = !hide))
                : null,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text), child: Text(action)),
        ],
      ),
    ),
  );
  c.dispose();
  return r;
}

/// Lets the user choose PDFs saved in the app or anywhere on the phone.
/// Locked PDFs are opened with a password (asked once) unless [keepLocked].
Future<List<PickedPdf>> pickPdfs(BuildContext context,
    {bool multiple = false, bool keepLocked = false, String? title}) async {
  final docs = await DocStore.instance.list();
  if (!context.mounted) return const [];
  final chosen = await showModalBottomSheet<List<Object>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PdfPickerSheet(
        docs: docs, multiple: multiple, title: title ?? 'Choose a PDF'),
  );
  if (chosen == null || chosen.isEmpty) return const [];
  final out = <PickedPdf>[];
  for (final c in chosen) {
    if (c is SavedDoc) {
      out.add(PickedPdf(c.name, await c.file.readAsBytes()));
    } else if (c is PlatformFile) {
      final n = c.name.toLowerCase().endsWith('.pdf')
          ? c.name.substring(0, c.name.length - 4)
          : c.name;
      out.add(PickedPdf(n, await c.readAsBytes()));
    }
  }
  if (keepLocked) return out;
  for (final p in out) {
    if (!PdfTools.isEncrypted(p.bytes)) continue;
    if (!context.mounted) return const [];
    final pw = await askText(context,
        title: '"${p.name}" is locked', hint: 'Password', password: true, action: 'Open');
    if (pw == null) return const [];
    try {
      final bytes = p.bytes;
      p.bytes = await bg(unlockJob, (bytes, pw));
    } on PasswordRequired {
      if (context.mounted) toast(context, 'Wrong password for "${p.name}".');
      return const [];
    }
  }
  return out;
}

class _PdfPickerSheet extends StatefulWidget {
  const _PdfPickerSheet(
      {required this.docs, required this.multiple, required this.title});
  final List<SavedDoc> docs;
  final bool multiple;
  final String title;

  @override
  State<_PdfPickerSheet> createState() => _PdfPickerSheetState();
}

class _PdfPickerSheetState extends State<_PdfPickerSheet> {
  final _picked = <Object>[];

  Future<void> _browse() async {
    final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: const ['pdf']);
    if (files.isEmpty || !mounted) return;
    if (!widget.multiple) {
      Navigator.pop(context, <Object>[files.first]);
      return;
    }
    setState(() => _picked.addAll(files));
  }

  @override
  Widget build(BuildContext context) {
    final phoneFiles = _picked.whereType<PlatformFile>().toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                    child: Text(widget.title,
                        style: Theme.of(context).textTheme.titleLarge)),
                if (widget.multiple)
                  FilledButton(
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.pop(context, List<Object>.of(_picked)),
                    child: Text('Use ${_picked.length}'),
                  ),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Browse phone files'),
              subtitle: phoneFiles.isEmpty
                  ? null
                  : Text(phoneFiles.map((f) => f.name).join(', '),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: _browse,
            ),
            const Divider(height: 1),
            if (widget.docs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No scans yet. Browse your phone files instead.'),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in widget.docs)
                    widget.multiple
                        ? CheckboxListTile(
                            value: _picked.contains(d),
                            secondary: _picked.contains(d)
                                ? CircleAvatar(
                                    radius: 14,
                                    child: Text('${_picked.indexOf(d) + 1}'))
                                : const Icon(Icons.picture_as_pdf),
                            title: Text(d.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(formatBytes(d.bytes)),
                            onChanged: (v) => setState(() =>
                                v == true ? _picked.add(d) : _picked.remove(d)),
                          )
                        : ListTile(
                            leading: const Icon(Icons.picture_as_pdf),
                            title: Text(d.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(formatBytes(d.bytes)),
                            onTap: () => Navigator.pop(context, <Object>[d]),
                          ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saves a tool's PDF result, refreshes the list and offers Open/Share.
Future<File?> saveResult(BuildContext context, String name, Uint8List pdf,
    {String? text}) async {
  final messenger = ScaffoldMessenger.of(context);
  final f = await DocStore.instance.savePdf(name, pdf);
  if (text != null) await DocStore.instance.saveText(f, text);
  docsChanged.value++;
  messenger.showSnackBar(SnackBar(
    content: Text('Saved "${f.uri.pathSegments.last}"'),
    action: SnackBarAction(
        label: 'Share', onPressed: () => shareFiles([f], mime: 'application/pdf')),
  ));
  return f;
}

