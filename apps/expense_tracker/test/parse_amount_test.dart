import 'dart:math';

import 'package:expense_tracker/data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gen.dart';

void main() {
  const wholes = [
    0, 1, 5, 9, 10, 12, 99, 100, 120, 999, 1000, 1234, 9999, 10000, 99999,
    100000, 123456, 1000000, 9999999, 123456789, 999999999999999,
  ];
  // suffix -> minor units it adds
  const fracs = {
    '': 0, '.': 0, '.0': 0, '.00': 0, '.5': 50, '.05': 5, '.50': 50,
    '.99': 99, '.1': 10, '.01': 1,
  };

  group('parseAmount whole x fraction table', () {
    for (final w in wholes) {
      for (final f in fracs.entries) {
        final input = '$w${f.key}';
        final v = w * 100 + f.value;
        final expected = v > 0 ? v : null;
        test('"$input" -> $expected', () {
          expect(parseAmount(input), expected);
        });
      }
    }
  });

  group('parseAmount accepts thousands separators', () {
    for (final w in wholes.where((w) => w >= 1000)) {
      for (final f in fracs.entries) {
        final input = '${groupThousands(w)}${f.key}';
        test('"$input" -> ${w * 100 + f.value}', () {
          expect(parseAmount(input), w * 100 + f.value);
        });
      }
    }
  });

  group('parseAmount trims surrounding whitespace', () {
    const pads = [(' ', ''), ('', ' '), ('  \t', '\n ')];
    for (final w in wholes.where((w) => w > 0)) {
      for (final (l, r) in pads) {
        final input = '$l$w.25$r';
        test('${Uri.encodeComponent(input)} -> ${w * 100 + 25}', () {
          expect(parseAmount(input), w * 100 + 25);
        });
      }
    }
  });

  group('parseAmount rejects invalid input', () {
    const bad = [
      '', ' ', 'abc', '12a', 'a12', '1.234', '0.001', '-5', '-0.5', '+5',
      '1e3', '1E3', '.5', '.', '..', '1..2', '1.2.3', '1 000', '12 .5',
      '\$12', '₹12', '12₹', 'Rs 12', '0x1F', 'NaN', 'Infinity', '１２',
      '1_000', '1\'000', '12,5.5.5', '0', '0.0', '0.00', '00', ',', ',,',
      '0,000.00', 'twelve', '12/5', '(12)', '12%', '1.2e2', '١٢', '½',
    ];
    for (final s in bad) {
      test('rejects ${Uri.encodeComponent(s)}', () {
        expect(parseAmount(s), isNull);
      });
    }
  });

  group('parseAmount comma quirks (commas are stripped anywhere)', () {
    const cases = {
      '1,2': 1200, '12,34': 123400, ',5': 500, '5,': 500, '1,,2': 1200,
      '1,2,3.4': 12340, '0,1': 100, '9,9,9,9': 999900,
    };
    cases.forEach((input, expected) {
      test('"$input" -> $expected', () {
        expect(parseAmount(input), expected);
      });
    });
  });

  group('parseAmount leading zeros', () {
    for (var z = 1; z <= 8; z++) {
      final input = '${'0' * z}42.07';
      test('"$input" -> 4207', () => expect(parseAmount(input), 4207));
    }
  });

  group('parseAmount huge values never throw or overflow', () {
    const huge = [
      '1000000000000000', '9999999999999999', '92233720368547758',
      '92233720368547758.07', '99999999999999999999',
      '123456789012345678901234567890', '1,000,000,000,000,000.00',
      '18446744073709551616', '9223372036854775807',
      '9223372036854775808.99',
    ];
    for (final s in huge) {
      test('"$s" -> null', () {
        expect(() => parseAmount(s), returnsNormally);
        expect(parseAmount(s), isNull);
      });
    }
    test('largest accepted value stays positive', () {
      expect(parseAmount('999999999999999.99'), 99999999999999999);
    });
  });

  group('parseAmount round-trips random amounts', () {
    final r = Random(1234);
    final seen = <int>{};
    while (seen.length < 120) {
      seen.add(randomAmount(r));
    }
    for (final a in seen) {
      final plain = plainAmount(a);
      test('plain "$plain" -> $a', () => expect(parseAmount(plain), a));
      final grouped = '${groupThousands(a ~/ 100)}.${plain.split('.')[1]}';
      if (grouped != plain) {
        test('grouped "$grouped" -> $a', () => expect(parseAmount(grouped), a));
      }
    }
  });

  group('parseAmount result invariants on random strings', () {
    final r = Random(99);
    const alphabet = '0123456789.,  ';
    final seen = <String>{};
    while (seen.length < 80) {
      final len = 1 + r.nextInt(10);
      seen.add(String.fromCharCodes(List.generate(
          len, (_) => alphabet.codeUnitAt(r.nextInt(alphabet.length)))));
    }
    for (final s in seen) {
      test('invariant for "$s"', () {
        final v = parseAmount(s);
        final t = s.replaceAll(',', '').trim();
        final valid = RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(t);
        if (!valid) {
          expect(v, isNull);
        } else {
          final asDouble = double.parse(t.endsWith('.') ? '${t}0' : t);
          final expected = (asDouble * 100).round();
          expect(v, expected > 0 ? expected : null);
        }
      });
    }
  });
}
