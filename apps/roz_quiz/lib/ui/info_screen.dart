import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'scope.dart';
import 'theme.dart';

/// A page of plain paragraphs: About, Sources & disclaimer.
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key, required this.title, required this.body});
  final String title;
  final List<String> body;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              Icon(Icons.lightbulb, color: context.colors.primary, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${context.s.t(T.appName)} · ${context.s.t(T.appTagline)}',
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 16),
            for (final p in body) ...[
              Text(p, style: context.text.bodyLarge?.copyWith(height: 1.5)),
              const SizedBox(height: 16),
            ],
          ],
        ),
      );
}
