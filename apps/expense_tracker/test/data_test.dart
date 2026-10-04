import 'package:expense_tracker/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseAmount reads whole and decimal amounts as minor units', () {
    expect(parseAmount('120'), 12000);
    expect(parseAmount('49.5'), 4950);
    expect(parseAmount('1,234.05'), 123405);
    expect(parseAmount('0'), isNull);
    expect(parseAmount('abc'), isNull);
    expect(parseAmount('1.234'), isNull);
  });

  test('CSV quotes notes and categories', () {
    final csv = toCsv([
      Expense(
          amount: 4950,
          category: 'food',
          date: DateTime(2026, 10, 5),
          note: 'Tea, "chai"'),
    ]);
    expect(csv, 'date,category,amount,note\n2026-10-05,"Food",49.50,"Tea, ""chai"""\n');
  });
}
