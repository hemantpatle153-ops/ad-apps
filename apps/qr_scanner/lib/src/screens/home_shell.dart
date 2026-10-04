import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'create_screen.dart';
import 'history_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['Scan', 'Create QR', 'History'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      // The camera only runs while the Scan tab is showing.
      body: switch (_tab) {
        0 => const ScanScreen(),
        1 => const CreateScreen(),
        _ => const HistoryScreen(),
      },
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BannerAdSlot(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
              NavigationDestination(
                  icon: Icon(Icons.add_box_outlined), label: 'Create'),
              NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            ],
          ),
        ],
      ),
    );
  }
}
