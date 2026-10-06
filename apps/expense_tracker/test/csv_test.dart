import 'dart:math';

import 'package:expense_tracker/data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gen.dart';

void main() {
  const header = 'date,category,amount,note\n';

  group('toCsv basics', () {
    test('empty list is just the header', () {
      expect(toCsv([]), header);
    });
    test('output ends with a newline', () {
      final csv = toCsv([Expense(amount: 1, category: 'food', date: DateTime(2026))]);
      expect(csv.endsWith('\n'), isTrue);
    });
    test('keeps list order (no re-sorting)', () {
      final csv = toCsv([
        Expense(amount: 1, category: 'food', date: DateTime(2026, 1, 2)),
        Expense(amount: 2, category: 'food', date: DateTime(2026, 1, 1)),
      ]);
      final rows = readCsv(csv);
      expect(rows[1][0], '2026-01-02');
      expect(rows[2][0], '2026-01-01');
    });
    test('unknown category exported as Other', () {
      final csv = toCsv([Expense(amount: 1, category: 'legacy', date: DateTime(2026))]);
      expect(readCsv(csv)[1][1], 'Other');
    });
    test('time of day is not exported', () {
      final csv = toCsv([
        Expense(amount: 100, category: 'rent', date: DateTime(2026, 3, 4, 23, 59, 59))
      ]);
      expect(csv, '${header}2026-03-04,"Rent",1.00,""\n');
    });
  });

  group('toCsv amount column', () {
    const amounts = {
      1: '0.01', 5: '0.05', 10: '0.10', 99: '0.99', 100: '1.00', 101: '1.01',
      4950: '49.50', 12000: '120.00', 123405: '1234.05', 99999999: '999999.99',
      100000000: '1000000.00', 123456789: '1234567.89',
    };
    amounts.forEach((minor, text) {
      test('$minor -> $text (no grouping, two decimals)', () {
        final csv = toCsv([Expense(amount: minor, category: 'food', date: DateTime(2026))]);
        expect(readCsv(csv)[1][2], text);
      });
    });
  });

  group('toCsv category column for every category', () {
    for (final c in Category.all) {
      test('${c.id} -> "${c.label}"', () {
        final csv = toCsv([Expense(amount: 100, category: c.id, date: DateTime(2026, 5, 6))]);
        expect(csv, '${header}2026-05-06,"${c.label}",1.00,""\n');
      });
    }
  });

  group('toCsv escapes notes', () {
    for (var i = 0; i < sampleNotes.length; i++) {
      final note = sampleNotes[i];
      test('note #$i ${Uri.encodeComponent(note)}', () {
        final csv = toCsv([Expense(amount: 250, category: 'gifts', date: DateTime(2026, 2, 3), note: note)]);
        final quoted = '"${note.replaceAll('"', '""')}"';
        expect(csv, '${header}2026-02-03,"Gifts",2.50,$quoted\n');
        final rows = readCsv(csv);
        expect(rows.length, 2);
        expect(rows[1], ['2026-02-03', 'Gifts', '2.50', note]);
      });
    }
  });

  group('toCsv date column pads month and day', () {
    for (var m = 1; m <= 12; m++) {
      for (final d in [1, 9, 10, 28]) {
        final date = DateTime(2024, m, d);
        test(refIsoDate(date), () {
          final csv = toCsv([Expense(amount: 1, category: 'food', date: date)]);
          expect(readCsv(csv)[1][0], refIsoDate(date));
        });
      }
    }
  });

  group('toCsv random lists round-trip through a CSV reader', () {
    final r = Random(555);
    for (var i = 0; i < 100; i++) {
      final n = r.nextInt(12);
      final list = [for (var k = 0; k < n; k++) randomExpense(r)];
      test('list #$i with $n rows', () {
        final rows = readCsv(toCsv(list));
        expect(rows.length, n + 1);
        expect(rows.first, ['date', 'category', 'amount', 'note']);
        for (var k = 0; k < n; k++) {
          final e = list[k];
          expect(rows[k + 1], [
            refIsoDate(e.date),
            Category.byId(e.category).label,
            plainAmount(e.amount),
            e.note,
          ]);
          expect(parseAmount(rows[k + 1][2]), e.amount);
        }
      });
    }
  });
}
