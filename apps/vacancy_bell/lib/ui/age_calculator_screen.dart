import 'package:flutter/material.dart';

import '../core/ymd.dart';
import '../l10n/s.dart';
import '../l10n/strings.dart';
import 'date_field.dart';
import 'scope.dart';

class AgeCalculatorScreen extends StatefulWidget {
  const AgeCalculatorScreen({super.key, this.initialOn});

  /// Pre-filled "age on" date (for example a notice's "as on" date).
  final Ymd? initialOn;

  @override
  State<AgeCalculatorScreen> createState() => _AgeCalculatorScreenState();
}

class _AgeCalculatorScreenState extends State<AgeCalculatorScreen> {
  Ymd? _birth;
  late Ymd _on;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _birth = app.settings.profile.dob;
    _on = widget.initialOn ?? app.today;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final theme = Theme.of(context);
    final today = app.today;
    final birth = _birth;
    final span = birth == null ? null : AgeSpan.between(birth, _on);
    final myDob = app.settings.profile.dob;

    return Scaffold(
      appBar: AppBar(title: Text(s.t(L.ageCalculator))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(s.t(L.ageCalcIntro)),
          ),
          DateTile(
            label: s.t(L.dateOfBirth),
            value: birth,
            onPick: () async {
              final d = await pickYmd(context,
                  initial: birth ?? today.addDays(-365 * 22),
                  first: Ymd(1940, 1, 1),
                  last: today);
              if (d != null) setState(() => _birth = d);
            },
          ),
          if (myDob != null && myDob != birth)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 64),
                child: TextButton(
                  onPressed: () => setState(() => _birth = myDob),
                  child: Text(s.t(L.useMyDob)),
                ),
              ),
            ),
          DateTile(
            label: s.t(L.ageOnDate),
            value: _on,
            icon: Icons.event_outlined,
            onPick: () async {
              final d = await pickYmd(context,
                  initial: _on, first: Ymd(1940, 1, 1), last: Ymd(today.year + 10, 12, 31));
              if (d != null) setState(() => _on = d);
            },
          ),
          const SizedBox(height: 16),
          if (birth != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: span == null
                  ? Text(s.t(L.ageInvalid), style: TextStyle(color: theme.colorScheme.error))
                  : AgeResultCard(span: span, s: s),
            ),
        ],
      ),
    );
  }
}

class AgeResultCard extends StatelessWidget {
  const AgeResultCard({super.key, required this.span, required this.s});
  final AgeSpan span;
  final S s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(int n, String label) => Expanded(
          child: Column(children: [
            Text('$n',
                style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700, color: theme.colorScheme.onPrimaryContainer)),
            Text(label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          ]),
        );
    return Semantics(
      label: s.t(L.ageResult, {'y': span.years, 'm': span.months, 'd': span.days}),
      excludeSemantics: true,
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          child: Column(children: [
            Row(children: [
              cell(span.years, s.t(L.years)),
              cell(span.months, s.t(L.months)),
              cell(span.days, s.t(L.days)),
            ]),
            const SizedBox(height: 12),
            Text(s.t(L.totalMonths, {'n': span.totalMonths}),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          ]),
        ),
      ),
    );
  }
}
