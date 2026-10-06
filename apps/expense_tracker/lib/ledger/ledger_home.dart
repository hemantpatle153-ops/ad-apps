import 'package:flutter/material.dart';

import '../data.dart';
import 'ledger_screen.dart';
import 'model.dart';
import 'service.dart';
import 'sheets.dart';
import 'store.dart';

/// Opens a log. A brand new one shows its code first, so it can be
/// shared straight away.
Future<void> openLedger(BuildContext context, LedgerService service,
        Settings settings, LocalLog local, {bool showCode = false}) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LedgerScreen(
            service: service,
            settings: settings,
            id: local.id,
            showCode: showCode)));

Future<void> startLedger(
    BuildContext context, LedgerService service, Settings settings) async {
  final local = await showCreateSheet(context, service);
  if (local == null || !context.mounted) return;
  await openLedger(context, service, settings, local, showCode: true);
}

Future<void> joinLedger(
    BuildContext context, LedgerService service, Settings settings) async {
  final local = await showJoinSheet(context, service);
  if (local == null || !context.mounted) return;
  await openLedger(context, service, settings, local);
}

/// The Ledger tab: every log on this phone with its result.
class LedgerHome extends StatefulWidget {
  const LedgerHome({super.key, required this.service, required this.settings});
  final LedgerService service;
  final Settings settings;

  @override
  State<LedgerHome> createState() => _LedgerHomeState();
}

class _LedgerHomeState extends State<LedgerHome> {
  static bool _cleaned = false;

  @override
  void initState() {
    super.initState();
    // Once per app run: delete cleared logs whose two weeks are over.
    if (!_cleaned) {
      _cleaned = true;
      widget.service.cleanUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final s = widget.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([service.store, s]),
      builder: (context, _) {
        final logs = service.store.all();
        if (logs.isEmpty) {
          return _Empty(
            onStart: () => startLedger(context, service, s),
            onJoin: () => joinLedger(context, service, s),
          );
        }
        var coming = 0, going = 0;
        for (final l in logs) {
          final log = l.log;
          if (log == null || log.isSettled || l.archived) continue;
          final b = log.balanceFor(l.side);
          if (b.net > 0) coming += b.net;
          if (b.net < 0) going -= b.net;
        }
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _Total(
                          label: 'Friends owe you',
                          value: s.money(coming),
                          color: comingColor(context)),
                    ),
                    Expanded(
                      child: _Total(
                          label: 'You owe friends',
                          value: s.money(going),
                          color: goingColor(context)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(
                      child: Text('Your ledgers',
                          style: theme.textTheme.titleSmall)),
                  TextButton.icon(
                    key: const Key('join-button'),
                    onPressed: () => joinLedger(context, service, s),
                    icon: const Icon(Icons.login),
                    label: const Text('Join with code'),
                  ),
                ],
              ),
            ),
            for (final l in logs)
              _LogTile(
                local: l,
                settings: s,
                nowMs: service.nowMs(),
                onTap: () => openLedger(context, service, s, l),
              ),
          ],
        );
      },
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        Text(value,
            style: theme.textTheme.titleLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.local,
    required this.settings,
    required this.nowMs,
    required this.onTap,
  });
  final LocalLog local;
  final Settings settings;
  final int nowMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final log = local.log;
    final friend = local.friendName;
    String line;
    Color? color;
    String? chip;
    if (log == null) {
      line = 'Waiting for the first sync…';
    } else {
      final b = log.balanceFor(local.side);
      line = resultLine(log, local.side, settings.money);
      color = b.isClear
          ? null
          : b.net > 0
              ? comingColor(context)
              : goingColor(context);
      if (local.archived) {
        chip = 'On this phone only';
      } else if (log.isSettled) {
        final d = log.daysLeft(nowMs);
        chip = 'Settled · removed in $d ${d == 1 ? 'day' : 'days'}';
        color = null;
      } else {
        chip = switch (log.stageFor(local.side)) {
          SettleStage.friendAsked => '$friend wants to settle up',
          SettleStage.waitingForFriend => 'Waiting for $friend',
          _ => null,
        };
      }
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(
              friend.isEmpty ? '?' : friend.characters.first.toUpperCase()),
        ),
        title: Text(friend, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(line,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            if (chip != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(chip, style: theme.textTheme.labelSmall),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onStart, required this.onJoin});
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.handshake_outlined,
                size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Track money with friends',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Record money you lend and borrow. Share a code with your friend '
              'and you both see the same entries, the same balance, and who '
              'owes whom.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('start-ledger'),
              onPressed: onStart,
              icon: const Icon(Icons.add),
              label: const Text('Start a shared ledger'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('join-ledger'),
              onPressed: onJoin,
              icon: const Icon(Icons.login),
              label: const Text('Join with a code'),
            ),
          ],
        ),
      ),
    );
  }
}
