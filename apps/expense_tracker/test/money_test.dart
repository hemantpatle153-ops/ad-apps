import 'dart:math';

import 'package:expense_tracker/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/gen.dart';

Future<Settings> settingsWith(String currency) async {
  SharedPreferences.setMockInitialValues({'currency': currency});
  return Settings(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('money with default rupee symbol', () {
    const table = {
      0: '₹0',
      1: '₹0.01',
      9: '₹0.09',
      10: '₹0.10',
      99: '₹0.99',
      100: '₹1',
      101: '₹1.01',
      4950: '₹49.50',
      12000: '₹120',
      99999: '₹999.99',
      100000: '₹1,000',
      123405: '₹1,234.05',
      999999: '₹9,999.99',
      1000000: '₹10,000',
      12345678: '₹123,456.78',
      100000000: '₹1,000,000',
      123456789012: '₹1,234,567,890.12',
      -1: '-₹0.01',
      -100: '-₹1',
      -4950: '-₹49.50',
      -123405: '-₹1,234.05',
      -100000000: '-₹1,000,000',
    };
    late Settings s;
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      s = Settings(await SharedPreferences.getInstance());
    });
    table.forEach((minor, expected) {
      test('$minor -> $expected', () => expect(s.money(minor), expected));
    });
  });

  group('money matches reference for every power-of-ten boundary', () {
    late Settings s;
    setUpAll(() async => s = await settingsWith('\$'));
    var p = 1;
    for (var i = 0; i <= 17; i++) {
      final base = p;
      for (final v in {base - 1, base, base + 1, base * 5 - 1}) {
        if (v < 0) continue;
        test('10^$i neighbour $v', () => expect(s.money(v), refMoney('\$', v)));
        if (v > 0) {
          test('10^$i neighbour -$v',
              () => expect(s.money(-v), refMoney('\$', -v)));
        }
      }
      p *= 10;
    }
  });

  const currencies = ['₹', '\$', '€', '£', '¥', 'Rs ', 'R\$', '₦', '₱', '৳'];
  const samples = [0, 5, 250, 4950, 100000, 123405, 98765432, -7, -250000];
  group('money for each supported currency', () {
    for (final c in currencies) {
      for (final v in samples) {
        test('"$c" $v -> ${refMoney(c, v)}', () async {
          final s = await settingsWith(c);
          expect(s.money(v), refMoney(c, v));
        });
      }
    }
  });

  group('money matches reference on random values', () {
    late Settings s;
    setUpAll(() async => s = await settingsWith('€'));
    final r = Random(42);
    final seen = <int>{};
    while (seen.length < 150) {
      final v = randomAmount(r) * (r.nextBool() ? 1 : -1);
      seen.add(v);
    }
    for (final v in seen) {
      test('random $v', () => expect(s.money(v), refMoney('€', v)));
    }
  });

  group('money output parses back with parseAmount', () {
    late Settings s;
    setUpAll(() async => s = await settingsWith(''));
    final r = Random(7);
    final seen = <int>{};
    while (seen.length < 120) {
      seen.add(randomAmount(r));
    }
    for (final v in seen) {
      test('round trip $v', () => expect(parseAmount(s.money(v)), v));
    }
  });

  group('money structural invariants', () {
    late Settings s;
    setUpAll(() async => s = await settingsWith('£'));
    final r = Random(2024);
    final seen = <int>{};
    while (seen.length < 60) {
      seen.add(randomAmount(r));
    }
    for (final v in seen) {
      test('invariants for $v', () {
        final out = s.money(v);
        expect(out.startsWith('£'), isTrue);
        expect(s.money(-v), '-$out');
        final body = out.substring(1).split('.');
        final groups = body[0].split(',');
        expect(groups.first.length, inInclusiveRange(1, 3));
        for (final g in groups.skip(1)) {
          expect(g.length, 3);
        }
        if (v % 100 == 0) {
          expect(body.length, 1);
        } else {
          expect(body[1].length, 2);
        }
      });
    }
  });
}
