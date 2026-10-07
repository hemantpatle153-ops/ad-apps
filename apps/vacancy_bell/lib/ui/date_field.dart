import 'package:flutter/material.dart';

import '../core/ymd.dart';
import '../l10n/strings.dart';
import 'scope.dart';

/// Opens the date picker and returns the chosen day.
Future<Ymd?> pickYmd(BuildContext context,
    {Ymd? initial, required Ymd first, required Ymd last}) async {
  final today = AppScope.read(context).today;
  var init = initial ?? today;
  if (init.isBefore(first)) init = first;
  if (init.isAfter(last)) init = last;
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime(init.year, init.month, init.day),
    firstDate: DateTime(first.year, first.month, first.day),
    lastDate: DateTime(last.year, last.month, last.day),
    initialEntryMode: DatePickerEntryMode.calendar,
  );
  return picked == null ? null : Ymd.ofDateTime(picked);
}

/// A list tile showing a date that opens the picker on tap.
class DateTile extends StatelessWidget {
  const DateTile({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
    this.icon = Icons.cake_outlined,
    this.onClear,
  });

  final String label;
  final Ymd? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value == null ? s.t(L.notSet) : s.date(value!)),
      trailing: value != null && onClear != null
          ? IconButton(
              tooltip: s.t(L.remove),
              icon: const Icon(Icons.close),
              onPressed: onClear,
            )
          : const Icon(Icons.edit_calendar_outlined),
      onTap: onPick,
    );
  }
}
