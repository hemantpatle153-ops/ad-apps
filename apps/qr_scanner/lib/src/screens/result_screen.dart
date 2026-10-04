import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../scan_kind.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final kind = ScanKind.of(value);
    final uri = ScanKind.launchUri(value);
    return Scaffold(
      appBar: AppBar(title: Text(kind.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(kind.icon, size: 32),
              const SizedBox(width: 12),
              Text(kind.label, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          if (uri != null)
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text(switch (kind) {
                ScanKind.upi => 'Pay with UPI app',
                ScanKind.product => 'Search product',
                ScanKind.phone => 'Call',
                ScanKind.email => 'Send email',
                _ => 'Open',
              }),
              onPressed: () =>
                  launchUrl(uri, mode: LaunchMode.externalApplication),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              }
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Share'),
            onPressed: () => SharePlus.instance.share(ShareParams(text: value)),
          ),
        ],
      ),
    );
  }
}
