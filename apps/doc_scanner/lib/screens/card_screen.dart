import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../contact_card.dart';
import '../doc_store.dart';
import '../ui_helpers.dart';

/// Details read from a business card, with "Save to contacts".
class CardScreen extends StatelessWidget {
  const CardScreen({super.key, required this.card, required this.text});
  final ContactCard card;
  final String text;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, List<String> values) => values.isEmpty
        ? const SizedBox.shrink()
        : Column(children: [
            for (final v in values)
              ListTile(
                leading: Icon(icon),
                title: SelectableText(v),
                subtitle: Text(label),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: v));
                    toast(context, 'Copied');
                  },
                ),
              ),
          ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Business card')),
      body: ListView(
        children: [
          if (card.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'No contact details were recognized. Try again with the card flat and well lit.'),
            ),
          row(Icons.person_outline, 'Name', [if (card.name.isNotEmpty) card.name]),
          row(Icons.business_outlined, 'Company', [if (card.company.isNotEmpty) card.company]),
          row(Icons.phone_outlined, 'Phone', card.phones),
          row(Icons.email_outlined, 'Email', card.emails),
          row(Icons.language, 'Website', card.websites),
          ExpansionTile(
            title: const Text('All text on the card'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(text),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: card.isEmpty
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Save to contacts'),
              onPressed: () async {
                final f = await DocStore.instance.saveExport(
                    '${card.name.isEmpty ? 'contact' : card.name}.vcf',
                    utf8.encode(card.toVCard()));
                shareFiles([f], mime: 'text/x-vcard');
              },
            ),
    );
  }
}
