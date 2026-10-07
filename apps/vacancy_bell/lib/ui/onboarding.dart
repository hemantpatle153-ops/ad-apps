import 'package:flutter/material.dart';

import '../core/json_read.dart';
import '../l10n/s.dart';
import '../l10n/strings.dart';
import '../models/taxonomy.dart';
import 'permission.dart';
import 'profile_screen.dart';
import 'scope.dart';
import 'theme.dart';

/// First run: language, interests, optional details. Every step can be
/// skipped.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _pages = PageController();
  int _page = 0;
  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final app = AppScope.read(context);
    final allowed = await ensureNotificationPermission(context);
    // Alerts stay on only when notifications can be shown.
    await app.setAlertPrefs(app.settings.alertPrefs.copyWith(enabled: allowed));
    await app.settings.setOnboarded();
  }

  void _next() {
    if (_page == _count - 1) {
      _finish();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  if (_page > 0)
                    IconButton(
                      tooltip: s.t(L.back),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _pages.previousPage(
                          duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _count; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => app.settings.setOnboarded(),
                    child: Text(s.t(L.skip)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [_LanguageStep(), _InterestsStep(), _DetailsStep()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(s.t(_page == _count - 1 ? L.done : L.continueLabel)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.icon, required this.title, this.hint, required this.child});
  final IconData icon;
  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: brandSaffron.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 32, color: brandSaffron),
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(title,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint!,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 24),
        child,
      ],
    );
  }
}

class _LanguageStep extends StatelessWidget {
  const _LanguageStep();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final theme = Theme.of(context);
    final current = app.settings.lang;
    return _StepScaffold(
      icon: Icons.translate,
      // Both languages, since the user hasn't chosen yet.
      title: '${S.en.t(L.chooseLanguage)}\n${S.hi.t(L.chooseLanguage)}',
      hint: app.s.t(L.chooseLanguageHint),
      child: Column(
        children: [
          for (final l in AppLang.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                color: current == l ? theme.colorScheme.primaryContainer : null,
                child: ListTile(
                  selected: current == l,
                  onTap: () => app.settings.setLang(l),
                  leading: Icon(current == l
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(S.of(l).languageName(l),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(S.of(l).t(L.appTagline)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InterestsStep extends StatelessWidget {
  const _InterestsStep();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final prefs = app.settings.alertPrefs;
    return _StepScaffold(
      icon: Icons.notifications_active_outlined,
      title: s.t(L.onbInterestsTitle),
      hint: s.t(L.onbInterestsHint),
      child: Wrap(
        spacing: 8,
        runSpacing: 10,
        children: [
          for (final c in JobCategory.values)
            FilterChip(
              label: Text(s.category(c)),
              selected: prefs.categories.contains(c),
              onSelected: (on) {
                final set = {...prefs.categories};
                on ? set.add(c) : set.remove(c);
                app.settings.setAlertPrefs(prefs.copyWith(categories: set));
              },
            ),
        ],
      ),
    );
  }
}

class _DetailsStep extends StatelessWidget {
  const _DetailsStep();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return _StepScaffold(
      icon: Icons.verified_outlined,
      title: s.t(L.onbDetailsTitle),
      hint: s.t(L.onbDetailsHint),
      child: const ProfileForm(compact: true),
    );
  }
}
