import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../player/play_item.dart';
import '../player/tool_sheets.dart';
import '../settings.dart';
import 'opensubtitles.dart';

/// Finds captions online for the playing video, downloads one and turns it
/// on. Searches by the exact file first (timing already fits), then by name.
class CaptionSearchSheet extends StatefulWidget {
  const CaptionSearchSheet({
    super.key,
    required this.player,
    required this.settings,
    required this.item,
    this.service,
  });

  final Player player;
  final Settings settings;
  final PlayItem item;
  final OpenSubtitles? service;

  @override
  State<CaptionSearchSheet> createState() => _CaptionSearchSheetState();
}

class _CaptionSearchSheetState extends State<CaptionSearchSheet> {
  late OpenSubtitles api = widget.service ??
      OpenSubtitles(apiKey: captionApiKey(widget.settings.openSubtitlesKey));
  final _key = TextEditingController();
  late final TextEditingController _query;
  late final CaptionQuery _parsed;
  late Set<String> _langs = {...widget.settings.captionLanguages};
  List<CaptionResult>? _results;
  String? _error;
  bool _busy = false;
  int? _downloading;
  String? _hash;

  @override
  void initState() {
    super.initState();
    _parsed = CaptionQuery.fromFileName(widget.item.title);
    _query = TextEditingController(text: _parsed.title);
    if (api.available) _search(firstTime: true);
  }

  @override
  void dispose() {
    _query.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _search({bool firstTime = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final path = widget.item.path ?? (widget.item.isNetwork ? null : widget.item.uri);
    if (firstTime && path != null && !path.startsWith('content:')) {
      _hash = await movieHash(path);
    }
    final typed = _query.text.trim();
    final query = typed == _parsed.title || typed.isEmpty
        ? _parsed
        : CaptionQuery.fromFileName(typed);
    try {
      final r = await api.search(
          hash: _hash, query: query, languages: _langs.isEmpty ? ['en'] : _langs.toList());
      if (mounted) setState(() => _results = r);
    } on CaptionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(CaptionResult r) async {
    setState(() => _downloading = r.fileId);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/captions');
      final path = await api.download(r, dir);
      await widget.player.setSubtitleTrack(
          SubtitleTrack.uri(path, title: '${captionLanguages[r.language] ?? r.language} (downloaded)'));
      widget.settings.setCaption(widget.item.key, path);
      if (mounted) Navigator.pop(context);
      messenger?.showSnackBar(SnackBar(
          content: Text(r.exactMatch
              ? 'Captions on. Made for this file, so the timing should fit.'
              : 'Captions on. If they are early or late, use Sync in Subtitles.')));
    } on CaptionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't save the caption file.");
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  void _saveKey() {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    widget.settings.setOpenSubtitlesKey(key);
    setState(() => api = OpenSubtitles(apiKey: captionApiKey(key)));
    _search(firstTime: true);
  }

  void _toggleLang(String code) {
    setState(() {
      _langs.contains(code) ? _langs.remove(code) : _langs.add(code);
      if (_langs.isEmpty) _langs = {'en'};
    });
    widget.settings.setCaptionLanguages(_langs.toList());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!api.available) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetTitle('Find captions online'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  'Captions come from OpenSubtitles.com. Get your own free key there '
                  '(sign in, then New consumer), copy it and paste it here once.'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openLink(openSubtitlesKeyPage),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Get a free key'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _key,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Paste your API key',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _saveKey(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _saveKey, child: const Text('Save')),
              ]),
            ),
          ]),
        ),
      );
    }
    final results = _results;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetTitle('Find captions online'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Movie or show name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _search, child: const Text('Search')),
            ]),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final e in captionLanguages.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FilterChip(
                      label: Text(e.value),
                      selected: _langs.contains(e.key),
                      onSelected: (_) => _toggleLang(e.key),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            ListTile(
              leading: Icon(Icons.error_outline_rounded, color: scheme.error),
              title: Text(_error!),
            ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              if (results != null && results.isEmpty && !_busy)
                const ListTile(
                  title: Text('No captions found'),
                  subtitle: Text('Try a shorter name, or add another language.'),
                ),
              for (final r in results ?? const <CaptionResult>[])
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                    child: Text(r.language.split('-').first.toUpperCase(),
                        style: TextStyle(color: scheme.primary, fontSize: 13)),
                  ),
                  title: Text(r.release, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    if (r.exactMatch) 'Fits this file',
                    '${r.downloads} downloads',
                    if (r.hearingImpaired) 'For hard of hearing',
                  ].join('  ·  ')),
                  trailing: _downloading == r.fileId
                      ? const SizedBox.square(
                          dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(r.exactMatch ? Icons.verified_rounded : Icons.download_rounded,
                          color: r.exactMatch ? scheme.primary : null),
                  onTap: _downloading == null ? () => _download(r) : null,
                ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Captions from OpenSubtitles.com',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ]),
      ),
    );
  }
}
