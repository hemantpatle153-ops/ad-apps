import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data.dart';
import 'backend.dart';
import 'model.dart';
import 'service.dart';
import 'store.dart';

/// Green for money coming to me, red for money I give.
Color comingColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);
Color goingColor(BuildContext context) => Theme.of(context).colorScheme.error;

/// Runs [action]; a problem shows as a snackbar. True when it worked.
Future<bool> runLedger(BuildContext context, Future<void> Function() action,
    {String? done}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    if (done != null) messenger?.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on LedgerException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger?.showSnackBar(
        SnackBar(content: Text(LedgerException.offline.message)));
  }
  return false;
}

String inviteText(LedgerLog log, Side me) =>
    '${log.nameOf(me)} invited you to a shared ledger in Daily Expense Tracker. '
    'Open the Friends tab, tap Join with code and enter ${prettyCode(log.code)}';

/// Start a new ledger: my name and my friend's. Returns the new log.
Future<LocalLog?> showCreateSheet(
        BuildContext context, LedgerService service) =>
    showModalBottomSheet<LocalLog>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateSheet(service: service),
    );

class _CreateSheet extends StatefulWidget {
  const _CreateSheet({required this.service});
  final LedgerService service;

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  late final _me = TextEditingController(text: widget.service.store.myName);
  final _friend = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _me.dispose();
    _friend.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (cleanName(_me.text).isEmpty || cleanName(_friend.text).isEmpty) {
      setState(() => _error = 'Enter both names');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final log = await widget.service.create(_me.text, _friend.text);
      if (mounted) Navigator.pop(context, log);
    } on LedgerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = LedgerException.offline.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Start a shared ledger',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('You get a code to share. Your friend joins with it, '
                'and both of you see the same log.'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('create-me'),
              controller: _me,
              maxLength: maxNameLength,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('create-friend'),
              controller: _friend,
              autofocus: true,
              maxLength: maxNameLength,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: "Friend's name",
                prefixIcon: const Icon(Icons.people_outline),
                border: const OutlineInputBorder(),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.handshake_outlined),
              label: const Text('Create ledger'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Join with a code: type or paste it, then pick which friend I am.
Future<LocalLog?> showJoinSheet(BuildContext context, LedgerService service,
        {String? code}) =>
    showModalBottomSheet<LocalLog>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _JoinSheet(service: service, code: code),
    );

class _JoinSheet extends StatefulWidget {
  const _JoinSheet({required this.service, this.code});
  final LedgerService service;
  final String? code;

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  late final _code = TextEditingController(text: widget.code ?? '');
  CodeInfo? _info;
  Side _side = Side.b;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final c = findJoinCode(data?.text ?? '');
    if (c != null) _code.text = prettyCode(c);
  }

  Future<void> _go(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } on LedgerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = LedgerException.offline.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _find() => _go(() async {
        final raw = findJoinCode(_code.text) ?? _code.text;
        final info = await widget.service.lookup(raw);
        final mine = widget.service.store.myName.toLowerCase();
        setState(() {
          _info = info;
          _side = info.nameA.toLowerCase() == mine && mine.isNotEmpty
              ? Side.a
              : Side.b;
        });
      });

  Future<void> _join() => _go(() async {
        final raw = findJoinCode(_code.text) ?? _code.text;
        final log = await widget.service.join(raw, _info!, _side);
        if (mounted) Navigator.pop(context, log);
      });

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Join with a code', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Ask your friend for the ledger code. It works '
                'on as many phones as you like.'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('join-code'),
              controller: _code,
              enabled: info == null,
              autofocus: widget.code == null,
              textCapitalization: TextCapitalization.characters,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(letterSpacing: 3, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Code',
                hintText: 'ABCD-2345',
                border: const OutlineInputBorder(),
                errorText: info == null ? _error : null,
                errorMaxLines: 3,
                suffixIcon: info == null
                    ? IconButton(
                        tooltip: 'Paste',
                        icon: const Icon(Icons.content_paste),
                        onPressed: _paste)
                    : null,
              ),
              onSubmitted: (_) => _find(),
            ),
            if (info != null) ...[
              const SizedBox(height: 16),
              Text('Ledger between ${info.nameA} and ${info.nameB}',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('Which one are you?'),
              const SizedBox(height: 8),
              SegmentedButton<Side>(
                segments: [
                  ButtonSegment(
                      value: Side.a,
                      label: Text(info.nameA, overflow: TextOverflow.ellipsis),
                      icon: const Icon(Icons.person_outline)),
                  ButtonSegment(
                      value: Side.b,
                      label: Text(info.nameB, overflow: TextOverflow.ellipsis),
                      icon: const Icon(Icons.person_outline)),
                ],
                selected: {_side},
                onSelectionChanged: (s) => setState(() => _side = s.first),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : (info == null ? _find : _join),
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(info == null ? Icons.search : Icons.login),
              label: Text(info == null
                  ? 'Find ledger'
                  : 'Join as ${info.nameOf(_side)}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the entry editor returns.
class EntryResult {
  const EntryResult(this.entry, {this.isNew = false, this.isDelete = false});
  final LedgerEntry entry;
  final bool isNew;
  final bool isDelete;
}

/// Add or edit one entry. [by] presets who paid for a new one.
Future<EntryResult?> showEntryEditor(
  BuildContext context, {
  required LedgerService service,
  required Settings settings,
  required LedgerLog log,
  required Side me,
  LedgerEntry? existing,
  Side? by,
}) =>
    showModalBottomSheet<EntryResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EntryEditor(
        service: service,
        settings: settings,
        log: log,
        me: me,
        existing: existing,
        by: by ?? me,
      ),
    );

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({
    required this.service,
    required this.settings,
    required this.log,
    required this.me,
    required this.by,
    this.existing,
  });
  final LedgerService service;
  final Settings settings;
  final LedgerLog log;
  final Side me;
  final Side by;
  final LedgerEntry? existing;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final _amount = TextEditingController(
      text: widget.existing == null
          ? ''
          : (widget.existing!.amount / 100)
              .toStringAsFixed(2)
              .replaceAll(RegExp(r'\.00$'), ''));
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _tag = TextEditingController(text: widget.existing?.tag ?? '');
  late Side _by = widget.existing?.by ?? widget.by;
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseAmount(_amount.text);
    if (v == null || v > maxEntryAmount) {
      setState(() => _error = v == null
          ? 'Enter an amount, for example 500 or 49.50'
          : 'That is too large for one entry');
      return;
    }
    final old = widget.existing;
    final entry = old == null
        ? widget.service.newEntry(
            amount: v, by: _by, date: _date, tag: _tag.text, note: _note.text)
        : old.copyWith(
            amount: v,
            by: _by,
            date: _date,
            tag: cleanText(_tag.text, maxTagLength),
            note: cleanText(_note.text, maxNoteLength));
    Navigator.pop(context, EntryResult(entry, isNew: old == null));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('It is removed for both of you.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, EntryResult(widget.existing!, isDelete: true));
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (d != null) {
      setState(() =>
          _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final friend = widget.log.nameOf(widget.me.other);
    final old = widget.existing;
    final iPaid = _by == widget.me;
    final color = iPaid ? comingColor(context) : goingColor(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(old == null ? 'New entry' : 'Edit entry',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            SegmentedButton<Side>(
              segments: [
                ButtonSegment(
                    value: widget.me,
                    icon: const Icon(Icons.call_made),
                    label: Text('I gave $friend',
                        overflow: TextOverflow.ellipsis)),
                ButtonSegment(
                    value: widget.me.other,
                    icon: const Icon(Icons.call_received),
                    label: Text('$friend gave me',
                        overflow: TextOverflow.ellipsis)),
              ],
              selected: {_by},
              onSelectionChanged: (s) => setState(() => _by = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              iPaid ? '$friend owes you this' : 'You owe $friend this',
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('entry-amount'),
              controller: _amount,
              autofocus: old == null,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.headlineSmall,
              decoration: InputDecoration(
                prefixText: widget.settings.currency,
                labelText: 'Amount',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Purpose', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: _tag,
              builder: (context, _) => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in purposeTags)
                    ChoiceChip(
                      label: Text(t),
                      selected:
                          _tag.text.trim().toLowerCase() == t.toLowerCase(),
                      onSelected: (on) => _tag.text = on ? t : '',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('entry-tag'),
              controller: _tag,
              maxLength: maxTagLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Purpose tag (pick or type your own)',
                prefixIcon: Icon(Icons.sell_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('entry-note'),
              controller: _note,
              maxLength: maxNoteLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(loc.formatFullDate(_date)),
              subtitle: const Text('Tap to change the date'),
              onTap: _pickDate,
            ),
            if (old != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(entryHistory(context, widget.log, old),
                    style: theme.textTheme.bodySmall),
              ),
            Row(
              children: [
                if (old != null)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _ms(BuildContext context, int ms) => MaterialLocalizations.of(context)
    .formatMediumDate(DateTime.fromMillisecondsSinceEpoch(ms));

/// "Added by Rahul on 6 Oct 2026 · Edited by Amit on 7 Oct 2026".
String entryHistory(BuildContext context, LedgerLog log, LedgerEntry e) {
  final parts = <String>[];
  if (e.createdAt > 0) {
    parts.add(e.createdBy == null
        ? 'Added on ${_ms(context, e.createdAt)}'
        : 'Added by ${log.nameOf(e.createdBy!)} on ${_ms(context, e.createdAt)}');
  }
  if (e.editedAt != null) {
    parts.add(e.editedBy == null
        ? 'Edited on ${_ms(context, e.editedAt!)}'
        : 'Edited by ${log.nameOf(e.editedBy!)} on ${_ms(context, e.editedAt!)}');
  }
  return parts.join(' · ');
}

/// The code, who is in, and reset.
Future<void> showCodeSheet(BuildContext context,
        {required LedgerService service,
        required LedgerLog log,
        required LocalLog local}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CodeSheet(service: service, log: log, local: local),
    );

class _CodeSheet extends StatefulWidget {
  const _CodeSheet(
      {required this.service, required this.log, required this.local});
  final LedgerService service;
  final LedgerLog log;
  final LocalLog local;

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  late String _code = widget.log.code;
  bool _busy = false;

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset the code?'),
        content: const Text(
            'The old code stops working for new phones. Phones already in '
            'this ledger stay in, and no entries are lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await runLedger(context, () async {
      final log = LedgerLog(
        id: widget.log.id,
        nameA: widget.log.nameA,
        nameB: widget.log.nameB,
        code: _code,
        settledAt: widget.log.settledAt,
      );
      final c = await widget.service.resetCode(log);
      if (mounted) setState(() => _code = c);
    }, done: 'New code ready');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final log = widget.log;
    final me = widget.local.side;
    String phones(Side s) {
      final n = log.devicesOf(s);
      return n == 1 ? '1 phone' : '$n phones';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ledger code', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('${log.nameOf(me.other)} joins with this code. It works on any '
              'number of phones and stays the same until you reset it.'),
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: SelectableText(
                prettyCode(_code),
                key: const Key('code-text'),
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                    letterSpacing: 4,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: prettyCode(_code)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied')));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => SharePlus.instance.share(ShareParams(
                      text: inviteText(
                          LedgerLog(
                              id: log.id,
                              nameA: log.nameA,
                              nameB: log.nameB,
                              code: _code),
                          me))),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices),
            title: Text('${log.nameA}: ${phones(Side.a)}'),
            subtitle: Text('${log.nameB}: ${phones(Side.b)}'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _reset,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset code'),
          ),
        ],
      ),
    );
  }
}
