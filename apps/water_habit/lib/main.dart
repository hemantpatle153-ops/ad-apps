import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'habits_view.dart';
import 'reminders.dart';
import 'settings_screen.dart';
import 'store.dart';
import 'water_view.dart';

const appPackageName = 'in.onlysoftware.water_habit';
// Rahul's published Google Doc (same text as website/build.py's page).
const privacyPolicyUrl =
    'https://docs.google.com/document/d/e/2PACX-1vSA3p-UvHEj2L2nIDLYeWIFo39PWUj8HU8qngDsyVkl4Eu_VXmlRnF8oBbCmL7SJ98_ziBsZA_iXNnN/pub';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.open();
  runApp(WaterHabitApp(store: store));
  // Consent and ads start after the first frame so the app opens instantly.
  AdService.instance.init(AdConfig.fromEnvironment());
  await Reminders.instance.init();
}

class WaterHabitApp extends StatelessWidget {
  const WaterHabitApp({super.key, required this.store});
  final AppStore store;

  static const _seed = Color(0xFF0288D1);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Water & Habit Reminder',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(_seed, Brightness.light),
      darkTheme: buildTheme(_seed, Brightness.dark),
      home: HomeShell(store: store),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final AppStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _firstRun();
  }

  /// On first launch, ask for notification permission and schedule the
  /// default water reminders.
  Future<void> _firstRun() async {
    final s = widget.store;
    if (s.onboarded) return;
    await Reminders.instance.requestPermission();
    await Reminders.instance.sync(s);
    s.onboarded = true;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_tab == 0 ? 'Water' : 'Habits'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SettingsScreen(store: s))),
            ),
          ],
        ),
        body: _tab == 0 ? WaterView(store: s) : HabitsView(store: s),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BannerAdSlot(),
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.water_drop_outlined),
                    selectedIcon: Icon(Icons.water_drop),
                    label: 'Water'),
                NavigationDestination(
                    icon: Icon(Icons.check_circle_outline),
                    selectedIcon: Icon(Icons.check_circle),
                    label: 'Habits'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
