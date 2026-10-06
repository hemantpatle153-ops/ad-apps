import 'dart:math';

import 'package:expense_tracker/data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gen.dart';

void main() {
  const expectedLabels = {
    'food': 'Food',
    'groceries': 'Groceries',
    'transport': 'Transport',
    'fuel': 'Fuel',
    'shopping': 'Shopping',
    'bills': 'Bills',
    'rent': 'Rent',
    'health': 'Health',
    'education': 'Education',
    'fun': 'Entertainment',
    'gifts': 'Gifts',
    'other': 'Other',
  };

  group('Category catalogue', () {
    test('has exactly the expected ids in order', () {
      expect(Category.all.map((c) => c.id).toList(), expectedLabels.keys.toList());
    });
    test('ids are unique', () {
      expect(Category.all.map((c) => c.id).toSet().length, Category.all.length);
    });
    test('labels are unique', () {
      expect(Category.all.map((c) => c.label).toSet().length, Category.all.length);
    });
    test('colors are unique', () {
      expect(Category.all.map((c) => c.color).toSet().length, Category.all.length);
    });
    test('icons are unique', () {
      expect(Category.all.map((c) => c.icon).toSet().length, Category.all.length);
    });
    test('fallback category is "other"', () {
      expect(Category.all.last.id, 'other');
    });

    for (final c in Category.all) {
      test('byId("${c.id}") returns the same category', () {
        expect(identical(Category.byId(c.id), c), isTrue);
      });
      test('${c.id} has label ${expectedLabels[c.id]}', () {
        expect(c.label, expectedLabels[c.id]);
      });
      test('${c.id} color is fully opaque', () {
        expect(c.color.a, 1.0);
      });
      test('${c.id} id is lowercase ascii', () {
        expect(RegExp(r'^[a-z]+$').hasMatch(c.id), isTrue);
      });
      test('byId is case-sensitive for ${c.id.toUpperCase()}', () {
        expect(Category.byId(c.id.toUpperCase()).id, 'other');
      });
      test('byId does not trim " ${c.id} "', () {
        final got = Category.byId(' ${c.id} ');
        expect(got.id, 'other');
      });
    }

    const unknown = [
      '', ' ', 'FOOD', 'Food', 'entertainment', 'Entertainment', 'grocery',
      'travel', 'misc', 'null', 'undefined', 'food ', 'fo od', '🍕', 'rent2',
      'bill', 'gift', 'Other', 'OTHER', '0',
    ];
    for (final id in unknown) {
      test('unknown id ${Uri.encodeComponent(id)} falls back to Other', () {
        final c = Category.byId(id);
        expect(c.id, 'other');
        expect(c.label, 'Other');
      });
    }
  });

  group('Expense.toRow', () {
    test('omits id when null', () {
      final e = Expense(amount: 1, category: 'food', date: DateTime(2026));
      expect(e.toRow().containsKey('id'), isFalse);
    });
    test('defaults note to empty string', () {
      final e = Expense(amount: 1, category: 'food', date: DateTime(2026));
      expect(e.note, '');
      expect(e.toRow()['note'], '');
    });
    test('stores date as epoch millis', () {
      final d = DateTime(2026, 10, 5, 13, 45, 12, 345);
      final e = Expense(amount: 1, category: 'food', date: d);
      expect(e.toRow()['date'], d.millisecondsSinceEpoch);
    });
    test('has exactly the expected keys with id', () {
      final e = Expense(id: 3, amount: 1, category: 'food', date: DateTime(2026));
      expect(e.toRow().keys.toSet(), {'id', 'amount', 'category', 'date', 'note'});
    });
  });

  group('Expense.fromRow', () {
    test('null note becomes empty string', () {
      final e = Expense.fromRow({
        'id': 1, 'amount': 200, 'category': 'fuel', 'date': 0, 'note': null,
      });
      expect(e.note, '');
    });
    test('missing note becomes empty string', () {
      final e = Expense.fromRow(
          {'id': 1, 'amount': 200, 'category': 'fuel', 'date': 0});
      expect(e.note, '');
    });
    test('keeps unknown category id verbatim', () {
      final e = Expense.fromRow(
          {'id': 1, 'amount': 200, 'category': 'legacy', 'date': 0, 'note': ''});
      expect(e.category, 'legacy');
    });
    test('missing id throws (rows from the db always have one)', () {
      expect(
          () => Expense.fromRow(
              {'amount': 200, 'category': 'fuel', 'date': 0, 'note': ''}),
          throwsA(isA<TypeError>()));
    });
  });

  group('Expense row round trip (random)', () {
    final r = Random(31337);
    for (var i = 0; i < 150; i++) {
      final e = randomExpense(r);
      test('#$i ${e.category} ${e.amount} ${e.date.toIso8601String()}', () {
        final back = Expense.fromRow(e.toRow());
        expect(back.id, e.id);
        expect(back.amount, e.amount);
        expect(back.category, e.category);
        expect(back.date, e.date);
        expect(back.note, e.note);
        expect(back.toRow(), e.toRow());
      });
    }
  });

  group('Expense row for every sample note', () {
    for (var i = 0; i < sampleNotes.length; i++) {
      final note = sampleNotes[i];
      test('note #$i ${Uri.encodeComponent(note)} survives the row', () {
        final e = Expense(
            id: i, amount: 100 + i, category: 'other', date: DateTime(2025, 1, i + 1), note: note);
        expect(Expense.fromRow(e.toRow()).note, note);
      });
    }
  });
}
