import 'package:flutter/material.dart';

import '../history_store.dart';
import '../scan_kind.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    HistoryStore.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HistoryStore.instance,
      builder: (context, _) {
        final entries = HistoryStore.instance.entries;
        if (entries.isEmpty) {
          return const Center(child: Text('Scanned codes will show up here.'));
        }
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final e = entries[i];
            final kind = ScanKind.of(e.value);
            return Dismissible(
              key: ValueKey(e.at),
              onDismissed: (_) => HistoryStore.instance.remove(e),
              child: ListTile(
                leading: Icon(kind.icon),
                title: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(MaterialLocalizations.of(context)
                    .formatShortDate(e.at)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ResultScreen(value: e.value)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
