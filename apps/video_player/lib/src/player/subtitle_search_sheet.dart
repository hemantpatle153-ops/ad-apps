import 'dart:io';

import 'package:flutter/material.dart';

import '../library/online_subtitles.dart';
import '../settings.dart';
import 'play_item.dart';
import 'subtitle_session.dart';

/// Searches subtitles for the playing video and loads the one tapped.
class SubtitleSearchSheet extends StatefulWidget {
  const SubtitleSearchSheet({
    super.key,
    required this.item,
    required this.session,
    required this.settings,
  });

  final PlayItem item;
  final SubtitleSession session;
  final Settings settings;

  @override
  State<SubtitleSearchSheet> createState() => _SubtitleSearchSheetState();
}

class _SubtitleSearchSheetState extends State<SubtitleSearchSheet> {
  late final _api = OnlineSubtitles(
      token: widget.settings.subtitleToken, host: widget.settings.subtitleHost);
  late final _query = TextEditingController(text: searchQueryFor(_fileName));
  late String _language = widget.settings.subtitleLanguage;
  String? _hash;
  bool _busy = false;
  String? _message;
  List<OnlineSubtitle>? _results;

  String get _fileName {
    final p = widget.item.path;
    return p != null ? p.split('/').last : widget.item.title;
  }

  @override
  void initState() {
    super.initState();
    if (onlineSubtitlesAvailable) _start();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final p = widget.item.path;
    if (p != null && !widget.item.isNetwork) {
      try {
        _hash = await movieHash(File(p));
      } catch (_) {}
    }
    await _search();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await _api.search(
          query: _query.text.trim(), language: _language, hash: _hash);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) _message = 'No subtitles found. Try a shorter name.';
      });
    } on SubtitleServiceException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'No connection. Check the internet and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(OnlineSubtitle s) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final path = await _api.download(s, widget.item.title);
      await widget.session.load(path, s.name);
      if (mounted) Navigator.pop(context, true);
    } on SubtitleServiceException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Download failed. Try another one.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!onlineSubtitlesAvailable) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Online subtitles are not available in this version. '
              'You can still load a subtitle file from the phone.'),
        ),
      );
    }
    final results = _results ?? const <OnlineSubtitle>[];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      labelText: 'Movie or show name',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: subtitleLanguages.containsKey(_language) ? _language : 'en',
                  items: [
                    for (final e in subtitleLanguages.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    widget.settings.setSubtitleLanguage(v);
                    setState(() => _language = v);
                    _search();
                  },
                ),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: _busy ? null : _search,
                ),
              ]),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_message!),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final s = results[i];
                  return ListTile(
                    leading: Icon(s.hashMatch
                        ? Icons.verified_rounded
                        : Icons.subtitles_outlined),
                    title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      subtitleLanguages[s.language] ?? s.language,
                      if (s.hashMatch) 'made for this file',
                      '${s.downloads} downloads',
                    ].join('  ·  ')),
                    onTap: _busy ? null : () => _download(s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
