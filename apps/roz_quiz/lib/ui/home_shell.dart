import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n/strings.dart';
import 'ca_tab.dart';
import 'practice_tab.dart';
import 'progress_tab.dart';
import 'scope.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'today_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  /// Tabs are built the first time they are opened, so the current affairs
  /// download waits until the user looks at it.
  final Set<int> _opened = {0};

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final titles = [T.appName, T.tabCurrent, T.tabPractice, T.progressTitle];
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_tab == 0) ...[
            const Icon(Icons.lightbulb, color: kBrand),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(s.t(titles[_tab]), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            key: const ValueKey('settings'),
            tooltip: s.t(T.settings),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          for (final (i, tab) in const [
            (0, TodayTab()),
            (1, CurrentAffairsTab()),
            (2, PracticeTab()),
            (3, ProgressTab()),
          ])
            _opened.contains(i) ? tab : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AppConfig.adsEnabled) const BannerAdSlot(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() {
              _tab = i;
              _opened.add(i);
            }),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.today_outlined),
                  selectedIcon: const Icon(Icons.today),
                  label: s.t(T.tabToday)),
              NavigationDestination(
                  icon: const Icon(Icons.newspaper_outlined),
                  selectedIcon: const Icon(Icons.newspaper),
                  label: s.t(T.tabCurrent)),
              NavigationDestination(
                  icon: const Icon(Icons.school_outlined),
                  selectedIcon: const Icon(Icons.school),
                  label: s.t(T.tabPractice)),
              NavigationDestination(
                  icon: const Icon(Icons.insights_outlined),
                  selectedIcon: const Icon(Icons.insights),
                  label: s.t(T.tabProgress)),
            ],
          ),
        ],
      ),
    );
  }
}
