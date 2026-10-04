import 'package:flutter/material.dart';

import 'data.dart';

class EditorResult {
  EditorResult(this.expense, {this.isDelete = false});
  final Expense expense;
  final bool isDelete;
}

/// Bottom sheet to add or edit one expense.
Future<EditorResult?> showExpenseEditor(
    BuildContext context, Settings settings, Expense? existing) {
  return showModalBottomSheet<EditorResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _Editor(settings: settings, existing: existing),
  );
}

class _Editor extends StatefulWidget {
  const _Editor({required this.settings, this.existing});
  final Settings settings;
  final Expense? existing;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final _amount = TextEditingController(
      text: widget.existing == null
          ? ''
          : (widget.existing!.amount / 100)
              .toStringAsFixed(2)
              .replaceAll(RegExp(r'\.00$'), ''));
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late String _category = widget.existing?.category ?? Category.all.first.id;
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseAmount(_amount.text);
    if (v == null) {
      setState(() => _error = 'Enter an amount, for example 120 or 49.50');
      return;
    }
    Navigator.pop(
      context,
      EditorResult(Expense(
        id: widget.existing?.id,
        amount: v,
        category: _category,
        date: _date,
        note: _note.text.trim(),
      )),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Add expense' : 'Edit expense',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: widget.existing == null,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: InputDecoration(
                prefixText: widget.settings.currency,
                labelText: 'Amount',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in Category.all)
                  ChoiceChip(
                    avatar: Icon(c.icon, size: 18, color: c.color),
                    label: Text(c.label),
                    selected: _category == c.id,
                    onSelected: (_) => setState(() => _category = c.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(loc.formatFullDate(_date)),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context,
                        EditorResult(widget.existing!, isDelete: true)),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
