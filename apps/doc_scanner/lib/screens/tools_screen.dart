import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../contact_card.dart';
import '../doc_store.dart';
import '../docx_writer.dart';
import '../image_filters.dart';
import '../jobs.dart';
import '../ocr.dart';
import '../page_ranges.dart';
import '../pdf_render.dart';
import '../pdf_tools.dart';
import '../review_screen.dart';
import '../scanner.dart';
import '../ui_helpers.dart';
import 'card_screen.dart';
import 'compare_screen.dart';
import 'organize_screen.dart';
import 'place_screen.dart';
import 'signature_pad.dart';
import 'text_screen.dart';

enum ToolGroup { scan, organize, optimize, convert, edit, security }

enum Tool {
  idCard('ID card', 'Both sides on one page', Icons.badge_outlined, ToolGroup.scan),
  businessCard('Business card', 'Read contact details', Icons.contact_mail_outlined, ToolGroup.scan),
  photos('Take photos', 'Camera photos to PDF', Icons.photo_camera_outlined, ToolGroup.scan),
  compare('Compare', 'Find changes between two documents', Icons.compare_outlined, ToolGroup.scan),
  merge('Merge PDF', 'Join PDFs into one', Icons.merge_type, ToolGroup.organize),
  split('Split PDF', 'Pull pages into new files', Icons.call_split, ToolGroup.organize),
  organize('Organize pages', 'Reorder, rotate, delete', Icons.view_agenda_outlined, ToolGroup.organize),
  rotate('Rotate PDF', 'Turn every page', Icons.rotate_90_degrees_cw_outlined, ToolGroup.organize),
  compress('Compress PDF', 'Make the file smaller', Icons.compress, ToolGroup.optimize),
  repair('Repair PDF', 'Rebuild a damaged file', Icons.build_outlined, ToolGroup.optimize),
  ocr('OCR PDF', 'Make a scan searchable', Icons.document_scanner_outlined, ToolGroup.optimize),
  pdfToJpg('PDF to JPG', 'Each page as an image', Icons.image_outlined, ToolGroup.convert),
  jpgToPdf('JPG to PDF', 'Photos into a PDF', Icons.picture_as_pdf_outlined, ToolGroup.convert),
  pdfToWord('PDF to Word', 'Editable text (.docx)', Icons.description_outlined, ToolGroup.convert),
  wordToPdf('Word to PDF', 'Text of a .docx as PDF', Icons.text_snippet_outlined, ToolGroup.convert),
  extractText('Extract text', 'Copy all the text', Icons.text_fields, ToolGroup.convert),
  sign('Sign PDF', 'Draw and place your signature', Icons.draw_outlined, ToolGroup.edit),
  addText('Add text', 'Type onto a page', Icons.title, ToolGroup.edit),
  watermark('Watermark', 'Stamp text across pages', Icons.branding_watermark_outlined, ToolGroup.edit),
  pageNumbers('Page numbers', 'Number every page', Icons.format_list_numbered, ToolGroup.edit),
  crop('Crop PDF', 'Trim page edges', Icons.crop, ToolGroup.edit),
  redact('Redact', 'Black out private details', Icons.format_color_fill, ToolGroup.security),
  protect('Protect PDF', 'Add a password', Icons.lock_outline, ToolGroup.security),
  unlock('Unlock PDF', 'Remove the password', Icons.lock_open_outlined, ToolGroup.security);

  const Tool(this.title, this.subtitle, this.icon, this.group);
  final String title;
  final String subtitle;
  final IconData icon;
  final ToolGroup group;

  /// Tools that work on one existing PDF (offered from a document's menu).
  bool get onePdf => !const {
        Tool.idCard,
        Tool.businessCard,
        Tool.photos,
        Tool.compare,
        Tool.jpgToPdf,
        Tool.wordToPdf,
      }.contains(this);
}

const _groupTitles = {
  ToolGroup.scan: 'Scan & compare',
  ToolGroup.organize: 'Organize',
  ToolGroup.optimize: 'Optimize',
  ToolGroup.convert: 'Convert',
  ToolGroup.edit: 'Edit & sign',
  ToolGroup.security: 'Security',
};

/// iLovePDF-style grid of every tool. All of them run on the phone.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      for (final g in ToolGroup.values) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Text(_groupTitles[g]!,
                style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverGrid.count(
            crossAxisCount: 3,
            childAspectRatio: 0.95,
            children: [
              for (final t in Tool.values.where((t) => t.group == g))
                _ToolTile(tool: t),
            ],
          ),
        ),
      ],
      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
    ]);
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => runTool(context, tool),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(tool.icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 8),
              Text(tool.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(tool.subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing the tools that apply to one document.
Future<void> showToolsFor(BuildContext context, PickedPdf pdf) async {
  final tool = await showModalBottomSheet<Tool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.75),
        child: ListView(shrinkWrap: true, children: [
          for (final t in Tool.values.where((t) => t.onePdf || t == Tool.merge))
            ListTile(
              leading: Icon(t.icon),
              title: Text(t.title),
              subtitle: Text(t.subtitle),
              onTap: () => Navigator.pop(c, t),
            ),
        ]),
      ),
    ),
  );
  if (tool != null && context.mounted) await runTool(context, tool, preset: pdf);
}

Future<PickedPdf?> _one(BuildContext context, PickedPdf? preset, {bool keepLocked = false}) async {
  if (preset != null) {
    if (keepLocked || !PdfTools.isEncrypted(preset.bytes)) return preset;
  }
  final list = preset != null
      ? await _unlockPreset(context, preset)
      : await pickPdfs(context, keepLocked: keepLocked);
  return list.isEmpty ? null : list.first;
}

Future<List<PickedPdf>> _unlockPreset(BuildContext context, PickedPdf p) async {
  final pw = await askText(context,
      title: '"${p.name}" is locked', hint: 'Password', password: true, action: 'Open');
  if (pw == null) return const [];
  try {
    p.bytes = await bg(unlockJob, (p.bytes, pw));
    return [p];
  } on PasswordRequired {
    if (context.mounted) toast(context, 'Wrong password.');
    return const [];
  }
}

Future<T?> _choice<T>(BuildContext context, String title, Map<T, String> options) =>
    showDialog<T>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: [
          for (final e in options.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(e.value),
              ),
            ),
        ],
      ),
    );

/// Runs [tool], asking for files and options as needed, then saves the
/// result next to the other documents.
Future<void> runTool(BuildContext context, Tool tool, {PickedPdf? preset}) async {
  try {
    await _run(context, tool, preset);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}

Future<void> _run(BuildContext context, Tool tool, PickedPdf? preset) async {
  Future<void> done(String name, Uint8List pdf, {String? text}) async {
    if (!context.mounted) return;
    await saveResult(context, name, pdf, text: text);
    // Natural break: a task just finished.
    AdService.instance.maybeShowInterstitial();
  }

  switch (tool) {
    case Tool.photos:
    case Tool.jpgToPdf:
      final paths = tool == Tool.photos ? await takePhotos(context) : await pickFromGallery();
      if (paths.isEmpty || !context.mounted) return;
      final saved = await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReviewScreen(pages: paths, title: tool == Tool.photos ? 'Photos' : 'Images')));
      if (saved != null) {
        docsChanged.value++;
        if (context.mounted) toast(context, 'PDF saved');
        AdService.instance.maybeShowInterstitial();
      }

    case Tool.idCard:
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('ID card'),
          content: const Text(
              'Scan the front, then the back. Both sides are placed at real size on one A4 page, ready to print.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Scan')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final pages = await scanPages(context, pageLimit: 2);
      if (pages.isEmpty || !context.mounted) return;
      final pdf = await busy(context, 'Building the ID card page', () async {
        final front = await readFileBytes(pages[0]);
        final back = pages.length > 1 ? await readFileBytes(pages[1]) : null;
        return DocStore.buildIdCardPdf(front, back);
      });
      if (pdf != null) await done('ID card', pdf);

    case Tool.businessCard:
      final pages = await scanPages(context, pageLimit: 1);
      if (pages.isEmpty || !context.mounted) return;
      final text = await busy(context, 'Reading the card', () async => (await Ocr.readFile(pages.first)).plain);
      if (text == null || !context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CardScreen(card: ContactCard.parse(text), text: text)));

    case Tool.compare:
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompareScreen()));

    case Tool.merge:
      var files = <PickedPdf>[if (preset != null) preset];
      final more = await pickPdfs(context,
          multiple: true, title: preset == null ? 'Choose PDFs in order' : 'Add PDFs after "${preset.name}"');
      files = [...files, ...more];
      if (files.length < 2) {
        if (context.mounted && more.isNotEmpty) toast(context, 'Choose at least two PDFs.');
        return;
      }
      if (!context.mounted) return;
      final out = await busy(context, 'Merging ${files.length} PDFs',
          () => bg(mergeJob, [for (final f in files) f.bytes]));
      if (out != null) await done('${files.first.name} merged', out);

    case Tool.wordToPdf:
      final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['docx']);
      if (f == null || !context.mounted) return;
      final name = f.name.replaceAll(RegExp(r'\.docx$', caseSensitive: false), '');
      final out = await busy(context, 'Converting', () async {
        final text = readDocxText(await f.readAsBytes());
        return DocStore.buildTextPdf(name, text);
      });
      if (out != null) await done(name, out);

    default:
      await _runOnePdf(context, tool, preset, done);
  }
}

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

Future<void> _runOnePdf(BuildContext context, Tool tool, PickedPdf? preset,
    Future<void> Function(String, Uint8List, {String? text}) done) async {
  final p = await _one(context, preset, keepLocked: tool == Tool.unlock);
  if (p == null || !context.mounted) return;
  final bytes = p.bytes;
  final name = p.name;

  switch (tool) {
    case Tool.split:
      final n = await bg(pageCountJob, bytes);
      if (!context.mounted) return;
      final mode = await _choice(context, 'Split "$name" ($n pages)', {
        'ranges': 'By page ranges (one file per range)',
        'every': 'Every N pages',
        'extract': 'Extract chosen pages into one file',
      });
      if (mode == null || !context.mounted) return;
      final input = await askText(context,
          title: switch (mode) {
            'ranges' => 'Ranges, e.g. 1-3, 4-$n',
            'every' => 'Pages per file',
            _ => 'Pages to keep, e.g. 1, 3-5',
          },
          initial: mode == 'every' ? '1' : '',
          keyboard: mode == 'every' ? TextInputType.number : TextInputType.text);
      if (input == null || !context.mounted) return;
      final List<List<int>> groups;
      try {
        groups = switch (mode) {
          'ranges' => parseSplitGroups(input, n),
          'every' => fixedGroups(n, int.tryParse(input.trim()) ?? 0),
          _ => [parsePageRange(input, n)],
        };
      } on FormatException catch (e) {
        toast(context, e.message);
        return;
      }
      final parts = await busy(context, 'Splitting', () => bg(splitJob, (bytes, groups)));
      if (parts == null || !context.mounted) return;
      for (var i = 0; i < parts.length; i++) {
        await DocStore.instance.savePdf(
            mode == 'extract' ? '$name pages' : '$name part ${i + 1}', parts[i]);
      }
      docsChanged.value++;
      if (context.mounted) toast(context, 'Saved ${parts.length} file${parts.length == 1 ? '' : 's'}');
      AdService.instance.maybeShowInterstitial();

    case Tool.organize:
      final pages = await Navigator.of(context).push<List<PageRef>>(
          MaterialPageRoute(builder: (_) => OrganizeScreen(pdf: bytes, name: name)));
      if (pages == null || !context.mounted) return;
      final out = await busy(context, 'Saving pages', () => bg(organizeJob, (bytes, pages)));
      if (out != null) await done('$name organized', out);

    case Tool.rotate:
      final turns = await _choice(context, 'Rotate every page',
          {1: '90° clockwise', 2: '180°', 3: '90° counter-clockwise'});
      if (turns == null || !context.mounted) return;
      final out = await busy(context, 'Rotating', () => bg(rotateJob, (bytes, turns)));
      if (out != null) await done('$name rotated', out);

    case Tool.compress:
      final strong = await _choice(context, 'Compress "$name" (${formatBytes(bytes.length)})', {
        false: 'Basic: lossless, keeps text selectable',
        true: 'Strong: much smaller, pages become images',
      });
      if (strong == null || !context.mounted) return;
      final out = await busy(context, 'Compressing',
          () => strong ? PdfRender.compressStrong(bytes) : bg(optimizeJob, bytes));
      if (out == null || !context.mounted) return;
      if (out.length >= bytes.length) {
        toast(context, 'This PDF is already as small as it gets.');
        return;
      }
      final pct = (100 - out.length * 100 / bytes.length).round();
      await done('$name compressed', out);
      if (context.mounted) {
        toast(context, '${formatBytes(bytes.length)} → ${formatBytes(out.length)} ($pct% smaller)');
      }

    case Tool.repair:
      final out = await busy(context, 'Repairing', () => bg(optimizeJob, bytes));
      if (out != null) await done('$name repaired', out);

    case Tool.ocr:
      final res = await busy(context, 'Reading text on every page', () async {
        final pngs = await PdfRender.pngs(bytes, dpi: 200);
        final texts = <PageText?>[];
        for (final png in pngs) {
          texts.add(await Ocr.readBytes(png));
        }
        final jpgs = [for (final png in pngs) await bg(processJob, (png, PageFilter.original, 0, 2400, 85))];
        final pdf = await DocStore.buildPdf(jpgs, PageSize.a4, text: texts);
        return (pdf, texts.map((t) => t?.plain ?? '').join('\n\n'));
      });
      if (res != null) await done('$name searchable', res.$1, text: res.$2);

    case Tool.extractText:
    case Tool.pdfToWord:
      final texts = await busy(context, 'Reading text', () => PdfRender.textWithOcr(bytes));
      if (texts == null || !context.mounted) return;
      if (tool == Tool.extractText) {
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TextScreen(name: name, pages: texts)));
      } else {
        final f = await DocStore.instance.saveExport('$name.docx', buildDocx(texts));
        shareFiles([f],
            mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        AdService.instance.maybeShowInterstitial();
      }

    case Tool.pdfToJpg:
      final files = await busy(context, 'Making images', () async {
        final jpgs = await PdfRender.jpgs(bytes);
        return [
          for (var i = 0; i < jpgs.length; i++)
            await DocStore.instance.saveExport('$name ${i + 1}.jpg', jpgs[i]),
        ];
      });
      if (files != null) {
        shareFiles(files, mime: 'image/jpeg');
        AdService.instance.maybeShowInterstitial();
      }

    case Tool.watermark:
      final text = await askText(context, title: 'Watermark text', initial: 'CONFIDENTIAL');
      if (text == null || text.trim().isEmpty || !context.mounted) return;
      final out = await busy(context, 'Adding watermark',
          () => bg(watermarkJob, (bytes, latin1Safe(text.trim()), 0.25)));
      if (out != null) await done('$name watermarked', out);

    case Tool.pageNumbers:
      final pos = await _choice(context, 'Where should numbers go?', {
        PageNumberPosition.bottomCenter: 'Bottom center',
        PageNumberPosition.bottomRight: 'Bottom right',
        PageNumberPosition.topRight: 'Top right',
      });
      if (pos == null || !context.mounted) return;
      final pattern = await _choice(context, 'Style', {
        '{n}': '1, 2, 3',
        '{n} / {total}': '1 / 10',
        'Page {n} of {total}': 'Page 1 of 10',
      });
      if (pattern == null || !context.mounted) return;
      final out = await busy(context, 'Numbering pages',
          () => bg(pageNumbersJob, (bytes, pos, pattern)));
      if (out != null) await done('$name numbered', out);

    case Tool.crop:
      final margins = await showDialog<List<double>>(
          context: context, builder: (_) => const _CropDialog());
      if (margins == null || !context.mounted) return;
      final out = await busy(context, 'Cropping',
          () => bg(cropJob, (bytes, margins[0], margins[1], margins[2], margins[3])));
      if (out != null) await done('$name cropped', out);

    case Tool.protect:
      final pw = await askText(context, title: 'Choose a password', password: true, action: 'Next');
      if (pw == null || pw.isEmpty || !context.mounted) return;
      final again = await askText(context, title: 'Type it again', password: true, action: 'Protect');
      if (again == null || !context.mounted) return;
      if (again != pw) {
        toast(context, "The passwords don't match.");
        return;
      }
      final out = await busy(context, 'Encrypting (AES-256)', () => bg(protectJob, (bytes, pw)));
      if (out != null) await done('$name protected', out);

    case Tool.unlock:
      if (!PdfTools.isEncrypted(bytes)) {
        toast(context, '"$name" has no password.');
        return;
      }
      final pw = await askText(context, title: 'Password for "$name"', password: true, action: 'Unlock');
      if (pw == null || !context.mounted) return;
      final out = await busy(context, 'Unlocking', () => bg(unlockJob, (bytes, pw)));
      if (out != null) await done('$name unlocked', out);

    case Tool.sign:
      final sig = await Navigator.of(context).push<(Uint8List, double)>(
          MaterialPageRoute(builder: (_) => const SignaturePadScreen()));
      if (sig == null || !context.mounted) return;
      final place = await Navigator.of(context).push<PlaceResult>(MaterialPageRoute(
          builder: (_) => PlaceScreen(
              pdf: bytes, what: ImagePlacement(sig.$1, sig.$2), title: 'Place signature')));
      if (place == null || !context.mounted) return;
      final out = await busy(context, 'Signing',
          () => bg(stampJob, (bytes, sig.$1, place.page, place.box)));
      if (out != null) await done('$name signed', out);

    case Tool.addText:
      final text = await askText(context, title: 'Text to add');
      if (text == null || text.trim().isEmpty || !context.mounted) return;
      final size = await _choice(context, 'Text size',
          {10.0: 'Small', 14.0: 'Medium', 20.0: 'Large', 32.0: 'Extra large'});
      if (size == null || !context.mounted) return;
      final clean = latin1Safe(text.trim());
      final place = await Navigator.of(context).push<PlaceResult>(MaterialPageRoute(
          builder: (_) => PlaceScreen(
              pdf: bytes,
              what: TextPlacement(clean, size, Colors.black),
              title: 'Place text')));
      if (place == null || !context.mounted) return;
      final out = await busy(context, 'Adding text',
          () => bg(addTextJob, (bytes, clean, place.page, place.box.topLeft, size, 0xFF000000)));
      if (out != null) await done('$name edited', out);

    case Tool.redact:
      final place = await Navigator.of(context).push<PlaceResult>(MaterialPageRoute(
          builder: (_) => PlaceScreen(pdf: bytes, what: const RedactPlacement(), title: 'Redact')));
      if (place == null || place.boxes.isEmpty || !context.mounted) return;
      final out = await busy(context, 'Redacting', () async {
        final covered = await bg(coverJob, (bytes, place.boxes));
        return PdfRender.flattenPages(covered, place.boxes.keys);
      });
      if (out != null) await done('$name redacted', out);

    default:
      break;
  }
}

class _CropDialog extends StatefulWidget {
  const _CropDialog();

  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  final _m = [0.05, 0.05, 0.05, 0.05];
  static const _labels = ['Left', 'Top', 'Right', 'Bottom'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Trim from each edge'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 4; i++)
          Row(children: [
            SizedBox(width: 56, child: Text(_labels[i])),
            Expanded(
              child: Slider(
                value: _m[i],
                max: 0.3,
                divisions: 30,
                onChanged: (v) => setState(() => _m[i] = v),
              ),
            ),
            SizedBox(width: 40, child: Text('${(_m[i] * 100).round()}%')),
          ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, List.of(_m)), child: const Text('Crop')),
      ],
    );
  }
}
