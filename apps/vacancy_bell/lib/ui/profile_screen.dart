import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/profile.dart';
import '../models/taxonomy.dart';
import 'date_field.dart';
import 'scope.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t(L.myDetails))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(s.t(L.myDetailsIntro))),
            ]),
          ),
          const ProfileForm(),
          if (!app.settings.profile.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => app.setProfile(UserProfile.empty),
                icon: const Icon(Icons.delete_outline),
                label: Text(s.t(L.clearDetails)),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "My details" fields; every change is saved at once.
class ProfileForm extends StatelessWidget {
  const ProfileForm({super.key, this.compact = false});

  /// Only date of birth and qualification (onboarding).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final p = app.settings.profile;
    final theme = Theme.of(context);
    final today = app.today;
    void save(UserProfile next) => app.setProfile(next);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(t, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DateTile(
          label: s.t(L.dateOfBirth),
          value: p.dob,
          onPick: () async {
            final d = await pickYmd(
              context,
              initial: p.dob ?? today.addDays(-365 * 22),
              first: today.addDays(-365 * 70),
              last: today.addDays(-365 * 10),
            );
            if (d != null) save(p.copyWith(dob: () => d));
          },
          onClear: () => save(p.copyWith(dob: () => null)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: DropdownButtonFormField<Qualification?>(
            key: ValueKey('q-${p.qualification}'),
            initialValue: p.qualification,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: s.t(L.highestQualification),
              prefixIcon: const Icon(Icons.school_outlined),
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: null, child: Text(s.t(L.notSet))),
              for (final q in Qualification.userLevels)
                DropdownMenuItem(value: q, child: Text(s.qualification(q))),
            ],
            onChanged: (v) => save(p.copyWith(qualification: () => v)),
          ),
        ),
        if (!compact) ...[
          label(s.t(L.socialCategory)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in SocialCategory.values)
                ChoiceChip(
                  label: Text(s.socialCategory(c)),
                  selected: p.category == c,
                  onSelected: (on) => save(p.copyWith(category: () => on ? c : null)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(s.t(L.pwbd)),
            value: p.pwbd,
            onChanged: (v) => save(p.copyWith(pwbd: v)),
          ),
          SwitchListTile(
            title: Text(s.t(L.exServiceman)),
            subtitle: p.exServiceman ? Text(s.t(L.exServicemanNote)) : null,
            value: p.exServiceman,
            onChanged: (v) => save(p.copyWith(exServiceman: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: DropdownButtonFormField<String?>(
              key: ValueKey('st-${p.state}'),
              initialValue: p.state,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: s.t(L.homeState),
                prefixIcon: const Icon(Icons.map_outlined),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: null, child: Text(s.t(L.notSet))),
                for (final st in indianStates)
                  DropdownMenuItem(value: st.code, child: Text(st.name(s.lang))),
              ],
              onChanged: (v) => save(p.copyWith(state: () => v)),
            ),
          ),
          label(s.t(L.gender)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in Gender.values)
                ChoiceChip(
                  label: Text(s.gender(g)),
                  selected: p.gender == g,
                  onSelected: (on) => save(p.copyWith(gender: () => on ? g : null)),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}
