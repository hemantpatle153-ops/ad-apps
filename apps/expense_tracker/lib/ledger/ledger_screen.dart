import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../data.dart';
import 'model.dart';
import 'service.dart';
import 'sheets.dart';
import 'store.dart';

enum _Filter { theyGive, iGive, all }

/// One ledger with a friend: the result, the two lists, and clearing it.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({
    super.key,
    required this.service,
    required this.settings,
    required this.id,
    this.showCode = false,
  });

  final LedgerService service;
  final Settings settings;
  final String id;

  /// Show the code sheet as soon as the log is loaded (a new log).
  final bool showCode;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late final StreamSubscription<LedgerLog?> _sub;
  LedgerLog? _log;

  /// The cloud copy is gone (deleted, or this phone left).
  bool _gone = false;
  bool _loading = true;
  _Filter _filter = _Filter.all;
  bool _codeShown = false;

  LedgerService get _service => widget.service;
  LocalLog? get _local => _service.store.byId(widget.id);

  @override
  void initState() {
    super.initState();
    final local = _local;
    _log = local?.log;
    _gone = local?.archived ?? false;
    _loading = _log == null && !_gone;
    _sub = _service.watch(widget.id).listen((log) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (log == null) {
          _gone = true;
        } else {
          _log = log;
          _gone = false;
        }
      });
      final local = _local;
      if (widget.showCode && !_codeShown && log != null && local != null) {
        _codeShown = true;
        showCodeSheet(context, service: _service, log: log, local: local);
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _edit(LedgerLog log, Side me,
      {LedgerEntry? existing, Side? by}) async {
    if (!log.editable || _gone) return;
    final r = await showEntryEditor(context,
        service: _service,
        settings: widget.settings,
        log: log,
        me: me,
        existing: existing,
        by: by);
    if (r == null || !mounted) return;
    final current = _log ?? log;
    await runLedger(
        context,
        () => r.isDelete
            ? _service.deleteEntry(current, r.entry.id)
            : _service.saveEntry(current, me, r.entry, isNew: r.isNew));
  }

  Future<void> _menu(String action, LedgerLog log, LocalLog local) async {
    switch (action) {
      case 'code':
        await showCodeSheet(context, service: _service, log: log, local: local);
      case 'rename':
        await _rename(log, local.side.other);
      case 'renameMe':
        await _rename(log, local.side);
      case 'switch':
        await runLedger(
            context, () => _service.switchSide(local, local.side.other),
            done: 'This phone is now ${log.nameOf(local.side.other)}');
        setState(() {});
      case 'leave':
        final ok = await _confirm(
            _gone ? 'Remove from this phone?' : 'Leave this ledger?',
            _gone
                ? 'The copy on this phone is deleted.'
                : 'This phone stops seeing the ledger. ${log.nameOf(local.side.other)} '
                    'keeps it, and you can join again with the code.',
            _gone ? 'Remove' : 'Leave');
        if (!ok || !mounted) return;
        if (await runLedger(context, () => _service.leave(local)) && mounted) {
          Navigator.pop(context);
        }
      case 'delete':
        final ok = await _confirm('Delete this ledger?',
            'It has no entries. It is deleted for both of you.', 'Delete');
        if (!ok || !mounted) return;
        if (await runLedger(context, () => _service.deleteEmpty(log)) &&
            mounted) {
          Navigator.pop(context);
        }
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
          ],
        ),
      ) ??
      false;

  Future<void> _rename(LedgerLog log, Side side) async {
    final c = TextEditingController(text: log.nameOf(side));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change name'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: maxNameLength,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (v == null || !mounted) return;
    await runLedger(context, () => _service.rename(log, side, v));
  }

  @override
  Widget build(BuildContext context) {
    final local = _local;
    final log = _log;
    if (local == null || log == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('This ledger is no longer available.',
                      textAlign: TextAlign.center),
                ),
        ),
      );
    }
    final me = local.side;
    final friend = log.nameOf(me.other);
    final s = widget.settings;
    final theme = Theme.of(context);
    final balance = log.balanceFor(me);
    final editable = log.editable && !_gone;

    final shown = log.entries.where((e) => switch (_filter) {
          _Filter.theyGive => e.by == me,
          _Filter.iGive => e.by != me,
          _Filter.all => true,
        });

    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(friend),
              Text('Ledger with ${log.nameOf(me)}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          actions: [
            if (!_gone && !log.isSettled)
              IconButton(
                tooltip: 'Code',
                icon: const Icon(Icons.key_outlined),
                onPressed: () => _menu('code', log, local),
              ),
            PopupMenuButton<String>(
              onSelected: (a) => _menu(a, log, local),
              itemBuilder: (_) => [
                if (!_gone) ...[
                  if (!log.isSettled)
                    const PopupMenuItem(
                        value: 'code', child: Text('Code and phones')),
                  PopupMenuItem(value: 'rename', child: Text('Rename $friend')),
                  const PopupMenuItem(
                      value: 'renameMe', child: Text('Change my name')),
                  PopupMenuItem(
                      value: 'switch', child: Text('This phone is $friend\'s')),
                  if (log.entries.isEmpty)
                    const PopupMenuItem(
                        value: 'delete', child: Text('Delete ledger')),
                ],
                PopupMenuItem(
                    value: 'leave',
                    child: Text(
                        _gone ? 'Remove from this phone' : 'Leave ledger')),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ResultCard(log: log, me: me, settings: s),
            if (_gone)
              _Banner(
                icon: Icons.phone_android,
                text: 'Saved on this phone only. The cloud copy was deleted, '
                    'so this is read-only.',
              )
            else
              _SettleCard(service: _service, log: log, me: me, settings: s),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<_Filter>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: _Filter.theyGive,
                      label: Text('$friend owes (${balance.theyGiveMeCount})',
                          overflow: TextOverflow.ellipsis)),
                  ButtonSegment(
                      value: _Filter.iGive,
                      label: Text('I owe (${balance.iGiveThemCount})',
                          overflow: TextOverflow.ellipsis)),
                  ButtonSegment(
                      value: _Filter.all,
                      label: Text('All (${log.entries.length})')),
                ],
                selected: {_filter},
                onSelectionChanged: (v) => setState(() => _filter = v.first),
              ),
            ),
            if (_filter != _Filter.all)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  _filter == _Filter.theyGive
                      ? '$friend owes you ${s.money(balance.theyGiveMe)} in total'
                      : 'You owe $friend ${s.money(balance.iGiveThem)} in total',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            if (log.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No entries yet. Add money you gave $friend or $friend gave '
                  'you, and both of you see it.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final e in shown)
              EntryTile(
                log: log,
                me: me,
                entry: e,
                settings: s,
                onTap: editable ? () => _edit(log, me, existing: e) : null,
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (editable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('add-i-gave'),
                          style: FilledButton.styleFrom(
                              backgroundColor: comingColor(context),
                              foregroundColor: Colors.white),
                          onPressed: () => _edit(log, me, by: me),
                          icon: const Icon(Icons.call_made),
                          label: Text('I gave $friend',
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('add-they-gave'),
                          style: FilledButton.styleFrom(
                              backgroundColor: goingColor(context),
                              foregroundColor: theme.colorScheme.onError),
                          onPressed: () => _edit(log, me, by: me.other),
                          icon: const Icon(Icons.call_received),
                          label: Text('$friend gave me',
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ),
              const BannerAdSlot(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The final ledger: who gives whom, and how it adds up.
class ResultCard extends StatelessWidget {
  const ResultCard(
      {super.key, required this.log, required this.me, required this.settings});
  final LedgerLog log;
  final Side me;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = log.balanceFor(me);
    final friend = log.nameOf(me.other);
    final money = settings.money;
    final color = b.isClear
        ? theme.colorScheme.onSurface
        : b.net > 0
            ? comingColor(context)
            : goingColor(context);
    final headline = resultLine(log, me, money);

    Widget row(String label, String value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(label, style: style)),
              Text(value, style: style),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balance', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(headline,
                key: const Key('result-line'),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
            const Divider(height: 24),
            row('$friend owes me', money(b.theyGiveMe),
                style: TextStyle(color: comingColor(context))),
            row('I owe $friend', '− ${money(b.iGiveThem)}',
                style: TextStyle(color: goingColor(context))),
            const Divider(height: 16),
            row(
              b.isClear
                  ? 'Nobody owes anything'
                  : '${log.nameOf(b.payer!)} pays ${log.nameOf(b.receiver!)}',
              money(b.amount),
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Amit will give you ₹500", from [me]'s side.
String resultLine(LedgerLog log, Side me, String Function(int) money) {
  final b = log.balanceFor(me);
  final friend = log.nameOf(me.other);
  if (b.isClear) return 'All settled';
  return b.net > 0
      ? '$friend owes you ${money(b.amount)}'
      : 'You owe $friend ${money(b.amount)}';
}

class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.log,
    required this.me,
    required this.entry,
    required this.settings,
    this.onTap,
  });
  final LedgerLog log;
  final Side me;
  final LedgerEntry entry;
  final Settings settings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final mine = entry.by == me;
    final color = mine ? comingColor(context) : goingColor(context);
    final friend = log.nameOf(me.other);
    final title = entry.note.isNotEmpty
        ? entry.note
        : entry.tag.isNotEmpty
            ? entry.tag
            : (mine ? 'You gave $friend' : '$friend gave you');
    final edited = entry.editedAt == null
        ? null
        : 'Edited ${loc.formatMediumDate(DateTime.fromMillisecondsSinceEpoch(entry.editedAt!))}'
            '${entry.editedBy == null ? '' : ' by ${log.nameOf(entry.editedBy!)}'}';
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .14),
        child: Icon(mine ? Icons.call_made : Icons.call_received, color: color),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (entry.tag.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(entry.tag,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer)),
                ),
              Text(loc.formatMediumDate(entry.date)),
            ],
          ),
          Text(mine ? '$friend owes you' : 'You owe $friend',
              style: theme.textTheme.bodySmall),
          if (edited != null)
            Text(edited,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
      isThreeLine: true,
      trailing: Text(
        '${mine ? '+' : '−'}${settings.money(entry.amount)}',
        style: theme.textTheme.titleMedium?.copyWith(color: color),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.icon, required this.text, this.actions = const []});
  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(text,
                        style: TextStyle(
                            color: theme.colorScheme.onSecondaryContainer))),
              ],
            ),
            if (actions.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: actions),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// Clearing the ledger: both friends confirm the same final amount.
class _SettleCard extends StatelessWidget {
  const _SettleCard({
    required this.service,
    required this.log,
    required this.me,
    required this.settings,
  });
  final LedgerService service;
  final LedgerLog log;
  final Side me;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final friend = log.nameOf(me.other);
    final loc = MaterialLocalizations.of(context);
    final result = resultLine(log, me, settings.money);
    if (log.entries.isEmpty && !log.isSettled) return const SizedBox.shrink();
    switch (log.stageFor(me)) {
      case SettleStage.settled:
        final at = log.settledAt;
        final now = service.nowMs();
        final days = log.daysLeft(now);
        return _Banner(
          icon: Icons.verified_outlined,
          text: at == null
              ? 'Both of you confirmed. Settling up…'
              : 'Settled on '
                  '${loc.formatMediumDate(DateTime.fromMillisecondsSinceEpoch(at))}. '
                  'This ledger is now read-only and will be removed from the '
                  'cloud ${days == 0 ? 'today' : 'in $days ${days == 1 ? 'day' : 'days'}'}. '
                  'A copy stays on this phone.',
          actions: [
            if (at != null)
              TextButton(
                onPressed: () => runLedger(context, () => service.reopen(log),
                    done: 'Ledger reopened'),
                child: const Text('Reopen'),
              ),
          ],
        );
      case SettleStage.waitingForFriend:
        return _Banner(
          icon: Icons.hourglass_top,
          text: 'You confirmed "$result". Waiting for $friend to confirm.',
          actions: [
            TextButton(
              onPressed: () =>
                  runLedger(context, () => service.withdraw(log, me)),
              child: const Text('Cancel request'),
            ),
          ],
        );
      case SettleStage.friendAsked:
        return _Banner(
          icon: Icons.mark_email_unread_outlined,
          text: '$friend wants to settle up: $result. Confirm if this is '
              'correct.',
          actions: [
            FilledButton(
              key: const Key('confirm-settle'),
              onPressed: () => runLedger(
                  context, () => service.approve(log, me),
                  done: 'Settled up'),
              child: const Text('Confirm'),
            ),
          ],
        );
      case SettleStage.open:
        return _Banner(
          icon: Icons.handshake_outlined,
          text: '${log.staleApprovalBy(me.other) ? 'The entries changed after '
                  '$friend asked to settle up. ' : ''}Ready to settle up? '
              'Once you both confirm "$result", the ledger is settled and removed '
              'from the cloud after $settledKeepDays days.',
          actions: [
            FilledButton.tonal(
              key: const Key('ask-settle'),
              onPressed: () => runLedger(
                  context, () => service.approve(log, me),
                  done: 'Sent to $friend to confirm'),
              child: const Text('Settle up'),
            ),
          ],
        );
    }
  }
}
