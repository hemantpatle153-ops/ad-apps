import 'dart:math';

import 'package:expense_tracker/data.dart';

/// Independent reference: groups digits of [n] (non-negative) with commas.
String groupThousands(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// Independent reference for [Settings.money].
String refMoney(String currency, int minor) {
  final neg = minor < 0;
  final v = minor.abs();
  final cents = v % 100;
  final c = cents == 0 ? '' : '.${cents < 10 ? '0$cents' : '$cents'}';
  return '${neg ? '-' : ''}$currency${groupThousands(v ~/ 100)}$c';
}

/// Independent reference for the CSV date column.
String refIsoDate(DateTime d) {
  String two(int x) => x < 10 ? '0$x' : '$x';
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// Plain "major.minor" text, e.g. 4950 -> "49.50".
String plainAmount(int minor) {
  final cents = minor % 100;
  return '${minor ~/ 100}.${cents < 10 ? '0$cents' : '$cents'}';
}

const sampleNotes = [
  '',
  'Tea',
  'Lunch with team',
  'Tea, "chai"',
  'a,b,c',
  '"quoted"',
  'line1\nline2',
  'Ümlaut café',
  '₹ symbol in note',
  'emoji 🍕',
  '   padded   ',
  'semi;colon',
  "it's",
  '""',
  ',',
];

int randomAmount(Random r) {
  switch (r.nextInt(4)) {
    case 0:
      return 1 + r.nextInt(100);
    case 1:
      return 1 + r.nextInt(100000);
    case 2:
      return 1 + r.nextInt(100000000);
    default:
      return (1 + r.nextInt(1 << 30)) * (1 + r.nextInt(1000));
  }
}

DateTime randomDate(Random r) => DateTime(
      2000 + r.nextInt(30),
      1 + r.nextInt(12),
      1 + r.nextInt(28),
      r.nextInt(24),
      r.nextInt(60),
      r.nextInt(60),
    );

Expense randomExpense(Random r, {bool withId = true}) => Expense(
      id: withId ? r.nextInt(1 << 31) : null,
      amount: randomAmount(r),
      category: Category.all[r.nextInt(Category.all.length)].id,
      date: randomDate(r),
      note: sampleNotes[r.nextInt(sampleNotes.length)],
    );

/// Minimal RFC 4180 reader used to check [toCsv] output independently.
List<List<String>> readCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
