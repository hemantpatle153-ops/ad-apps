import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'editor.dart';
import 'ledger/backend.dart';
import 'ledger/ledger_home.dart';
import 'ledger/service.dart';
import 'ledger/store.dart';
import 'insights.dart';
import 'settings_screen.dart';

const appPackageName = 'in.onlysoftware.expense_tracker';
const privacyPolicyUrl =
    'https://example.com/privacy'; // TODO: your hosted policy

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await ExpenseDb.open();
  final settings = await Settings.load();
  // Firebase starts only when the Ledger tab is used, so the app opens fast
  // and works offline as before.
  final ledger =
      LedgerService(FirebaseLedgerBackend(), await LedgerStore.load());
  runApp(ExpenseApp(db: db, settings: settings, ledger: ledger));
  // Consent and ads start after the first frame so the app opens instantly.
  AdService.instance.init(AdConfig.fromEnvironment());
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp(
      {super.key,
      required this.db,
      required this.settings,
      required this.ledger});
  final ExpenseDb db;
  final Settings settings;
  final LedgerService ledger;

  static const _seed = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(_seed, Brightness.light),
      darkTheme: buildTheme(_seed, Brightness.dark),
      home: HomeShell(db: db, settings: settings, ledger: ledger),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell(
      {super.key,
      required this.db,
      required this.settings,
      required this.ledger});
  final ExpenseDb db;
  final Settings settings;
  final LedgerService ledger;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<Expense>> _items = widget.db.month(_month);
  int _savesSinceAd = 0;

  void _reload() => setState(() => _items = widget.db.month(_month));

  void _shiftMonth(int delta) {
    _month = DateTime(_month.year, _month.month + delta);
    _reload();
  }

  Future<void> _edit([Expense? e]) async {
    final saved = await showExpenseEditor(context, widget.settings, e);
    if (saved == null) return;
    if (saved.isDelete) {
      await widget.db.delete(saved.expense.id!);
    } else {
      await widget.db.save(saved.expense);
    }
    _reload();
    // Logging an expense takes seconds, so ads only come after a few saves.
    if (++_savesSinceAd >= 3) {
      _savesSinceAd = 0;
      AdService.instance.maybeShowInterstitial();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final monthLabel =
        MaterialLocalizations.of(context).formatMonthYear(_month);
    final isCurrent = _month.year == DateTime.now().year &&
        _month.month == DateTime.now().month;
    final ledgerTab = _tab == 2;
    return ListenableBuilder(
      listenable: Listenable.merge([s, widget.ledger.store]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: ledgerTab
              ? const Text('Friends')
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => _shiftMonth(-1),
                        icon: const Icon(Icons.chevron_left)),
                    Text(monthLabel),
                    IconButton(
                        tooltip: 'Next month',
                        onPressed: isCurrent ? null : () => _shiftMonth(1),
                        icon: const Icon(Icons.chevron_right)),
                  ],
                ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        SettingsScreen(db: widget.db, settings: s)));
                _reload();
              },
            ),
          ],
        ),
        body: ledgerTab
            ? LedgerHome(service: widget.ledger, settings: s)
            : FutureBuilder<List<Expense>>(
                future: _items,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data!;
                  return _tab == 0
                      ? _ExpenseList(
                          items: list, settings: s, month: _month, onTap: _edit)
                      : InsightsView(items: list, settings: s, month: _month);
                },
              ),
        floatingActionButton: _tab == 0
            ? FloatingActionButton.extended(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add expense'),
              )
            : ledgerTab && widget.ledger.store.all().isNotEmpty
                ? FloatingActionButton.extended(
                    key: const Key('new-ledger'),
                    onPressed: () => startLedger(context, widget.ledger, s),
                    icon: const Icon(Icons.handshake_outlined),
                    label: const Text('New ledger'),
                  )
                : null,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BannerAdSlot(),
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.list_alt), label: 'Expenses'),
                NavigationDestination(
                    icon: Icon(Icons.pie_chart_outline), label: 'Insights'),
                NavigationDestination(
                    icon: Icon(Icons.handshake_outlined), label: 'Friends'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({
    required this.items,
    required this.settings,
    required this.month,
    required this.onTap,
  });

  final List<Expense> items;
  final Settings settings;
  final DateTime month;
  final void Function(Expense) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = items.fold<int>(0, (a, e) => a + e.amount);
    final now = DateTime.now();
    final today = items
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            e.date.day == now.day)
        .fold<int>(0, (a, e) => a + e.amount);
    final budget = settings.budget;
    final loc = MaterialLocalizations.of(context);

    final children = <Widget>[
      Card(
        margin: const EdgeInsets.all(16),
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spent this month', style: theme.textTheme.labelLarge),
              Text(settings.money(total),
                  style: theme.textTheme.headlineMedium),
              if (month.year == now.year && month.month == now.month)
                Text('Today: ${settings.money(today)}'),
              if (budget > 0) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (total / budget).clamp(0, 1).toDouble(),
                  color: total > budget ? theme.colorScheme.error : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                Text(total > budget
                    ? 'Over budget by ${settings.money(total - budget)}'
                    : '${settings.money(budget - total)} left of ${settings.money(budget)}'),
              ],
            ],
          ),
        ),
      ),
    ];

    if (items.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.all(32),
        child: Text('No expenses this month. Tap Add expense to log one.',
            textAlign: TextAlign.center),
      ));
    }

    DateTime? day;
    for (final e in items) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      if (d != day) {
        day = d;
        final dayTotal = items
            .where((x) =>
                x.date.year == d.year &&
                x.date.month == d.month &&
                x.date.day == d.day)
            .fold<int>(0, (a, x) => a + x.amount);
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                  child: Text(loc.formatFullDate(d),
                      style: theme.textTheme.titleSmall)),
              Text(settings.money(dayTotal), style: theme.textTheme.titleSmall),
            ],
          ),
        ));
      }
      final c = Category.byId(e.category);
      children.add(ListTile(
        leading: CircleAvatar(
          backgroundColor: c.color.withValues(alpha: .15),
          child: Icon(c.icon, color: c.color),
        ),
        title: Text(e.note.isEmpty ? c.label : e.note,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: e.note.isEmpty ? null : Text(c.label),
        trailing:
            Text(settings.money(e.amount), style: theme.textTheme.titleMedium),
        onTap: () => onTap(e),
      ));
    }
    children.add(const SizedBox(height: 88));
    return ListView(children: children);
  }
}
