import 'package:flutter/material.dart';

import '../core/bi.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import '../l10n/strings.dart';
import 'permissions.dart';
import 'scope.dart';
import 'theme.dart';

/// First run: language, target exams, daily reminder. Every step can be
/// skipped; the choices can be changed later in Settings.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  final Set<String> _exams = {};
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) {
    setState(() => _page = page);
    _pages.animateToPage(page,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  Future<void> _finish({required bool reminders}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final app = AppScope.read(context);
    var granted = false;
    if (reminders) granted = await ensureNotifications(context, explain: false);
    await app.updateSettings((s) {
      s.targetExams = [for (final e in kExams) if (_exams.contains(e)) e];
      s.dailyReminder = granted;
      s.streakReminder = granted;
      s.onboarded = true;
    }, reschedule: true);
  }

  Future<void> _pickTime() async {
    final app = AppScope.read(context);
    final m = app.settings.reminderMinutes;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t != null) {
      await app.updateSettings((s) => s.reminderMinutes = t.hour * 60 + t.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = context.s;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                for (var i = 0; i < 3; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? context.colors.primary
                          : context.colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  key: const ValueKey('obSkip'),
                  onPressed: _busy ? null : () => _finish(reminders: false),
                  child: Text(s.t(T.obSkip)),
                ),
              ]),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Page(
                    icon: Icons.lightbulb,
                    title: s.t(T.obWelcome),
                    subtitle: s.t(T.obWelcomeSub),
                    child: Column(children: [
                      Text(s.t(T.obChooseLanguage),
                          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      for (final (lang, label, sub) in const [
                        (Lang.en, 'English', 'Questions and app in English'),
                        (Lang.hi, 'हिंदी', 'प्रश्न और ऐप हिंदी में'),
                      ]) ...[
                        _LangCard(
                          key: ValueKey('lang-${lang.name}'),
                          label: label,
                          sub: sub,
                          selected: app.lang == lang,
                          onTap: () => app.updateSettings((x) => x.lang = lang),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ]),
                  ),
                  _Page(
                    icon: Icons.school,
                    title: s.t(T.obExamsTitle),
                    subtitle: s.t(T.obExamsSub),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final e in kExams)
                          FilterChip(
                            avatar: Icon(examIcon(e), size: 18),
                            label: Text(s.exam(e)),
                            selected: _exams.contains(e),
                            onSelected: (v) =>
                                setState(() => v ? _exams.add(e) : _exams.remove(e)),
                          ),
                      ],
                    ),
                  ),
                  _Page(
                    icon: Icons.notifications_active,
                    title: s.t(T.obReminderTitle),
                    subtitle: s.t(T.obReminderSub),
                    child: Column(children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.alarm),
                          title: Text('${formatMinutes(app.settings.reminderMinutes)} IST',
                              style: context.text.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          trailing: TextButton(
                              onPressed: _pickTime, child: Text(s.t(T.obChangeTime))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(s.t(T.permBody),
                          textAlign: TextAlign.center,
                          style: context.text.bodyMedium
                              ?.copyWith(color: context.colors.onSurfaceVariant)),
                    ]),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _page < 2
                  ? SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('obContinue'),
                        onPressed: () => _go(_page + 1),
                        child: Text(s.t(T.obContinue)),
                      ),
                    )
                  : Column(children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('obAllow'),
                          onPressed: _busy ? null : () => _finish(reminders: true),
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: Text(s.t(T.allow)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          key: const ValueKey('obNotNow'),
                          onPressed: _busy ? null : () => _finish(reminders: false),
                          child: Text(s.t(T.notNow)),
                        ),
                      ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kBrand, Color(0xFF0B6E73)]),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(icon, size: 48, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 24),
          child,
        ]),
      );
}

class _LangCard extends StatelessWidget {
  const _LangCard({
    super.key,
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? context.colors.primaryContainer : context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: selected ? context.colors.primary : context.colors.outlineVariant,
                width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(sub, style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: context.colors.primary),
              ]),
            ),
          ),
        ),
      );
}
