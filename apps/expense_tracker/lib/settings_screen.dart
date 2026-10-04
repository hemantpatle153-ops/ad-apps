import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'data.dart';
import 'main.dart' show appPackageName, privacyPolicyUrl;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.db, required this.settings});
  final ExpenseDb db;
  final Settings settings;

  static const _currencies = ['₹', '\$', '€', '£', '¥', 'Rs ', 'R\$', '₦', '₱', '৳'];

  Future<void> _setBudget(BuildContext context) async {
    final c = TextEditingController(
        text: settings.budget == 0 ? '' : (settings.budget ~/ 100).toString());
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Monthly budget'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              prefixText: settings.currency, helperText: 'Leave empty for none'),
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
    if (v == null) return;
    settings.budget = v.trim().isEmpty ? 0 : (parseAmount(v) ?? settings.budget);
  }

  Future<void> _export(BuildContext context) async {
    final all = await db.all();
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/expenses.csv');
    await f.writeAsString(toCsv(all));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'text/csv')],
      subject: 'Expenses export',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        bottomNavigationBar: const BannerAdSlot(),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: const Text('Currency symbol'),
              trailing: DropdownButton<String>(
                value: _currencies.contains(settings.currency)
                    ? settings.currency
                    : _currencies.first,
                items: [
                  for (final c in _currencies)
                    DropdownMenuItem(value: c, child: Text(c.trim())),
                ],
                onChanged: (v) {
                  if (v != null) settings.currency = v;
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Monthly budget'),
              subtitle: Text(settings.budget == 0
                  ? 'Not set'
                  : settings.money(settings.budget)),
              onTap: () => _setBudget(context),
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export to CSV'),
              subtitle: const Text('Share every expense as a spreadsheet file'),
              onTap: () => _export(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Rate this app'),
              onTap: () => openStorePage(appPackageName),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              onTap: () => openLink(privacyPolicyUrl),
            ),
            FutureBuilder<bool>(
              future: AdService.instance.privacyOptionsRequired(),
              builder: (context, snap) => snap.data == true
                  ? ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Ad privacy choices'),
                      onTap: AdService.instance.showPrivacyOptions,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
