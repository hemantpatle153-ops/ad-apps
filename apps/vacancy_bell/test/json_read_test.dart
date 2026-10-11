import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/json_read.dart';

void main() {
  group('readInt', () {
    final cases = <(Object?, int?)>[
      (5, 5),
      (0, 0),
      (-3, -3),
      (12.0, 12),
      (12.5, null),
      (double.nan, null),
      (double.infinity, null),
      ('42', 42),
      (' 42 ', 42),
      ('1,200', 1200),
      ('14,582', 14582),
      ('12a', null),
      ('', null),
      (null, null),
      (true, null),
      ([1], null),
      ({'n': 1}, null),
    ];
    for (final (v, want) in cases) {
      test('$v -> $want', () => expect(readInt(v), want));
    }
    test('min and max bounds', () {
      expect(readInt(5, min: 10), isNull);
      expect(readInt(50, max: 40), isNull);
      expect(readInt(30, min: 10, max: 40), 30);
      expect(readInt(10, min: 10, max: 10), 10);
    });
  });

  group('readString', () {
    test('trims and drops control characters', () {
      expect(readString('  hi\u0000 there\u0007 '), 'hi there');
    });
    test('keeps newlines and tabs inside', () {
      expect(readString('a\nb\tc'), 'a\nb\tc');
    });
    test('empty and non-strings are null', () {
      expect(readString('   '), isNull);
      expect(readString(5), isNull);
      expect(readString(null), isNull);
    });
    test('cuts very long text', () {
      expect(readString('x' * 50, maxLength: 10), 'x' * 10);
    });
  });

  group('readUrl keeps only http(s) links with a host', () {
    final cases = <(Object?, bool)>[
      ('https://ssc.gov.in', true),
      ('https://ssc.gov.in/notice.pdf', true),
      ('http://upsc.gov.in/exams', true),
      ('  https://ibps.in/  ', true),
      ('https://www.rrbcdg.gov.in/page?id=1#top', true),
      ('javascript:alert(1)', false),
      ('ftp://example.com/file.pdf', false),
      ('file:///etc/passwd', false),
      ('intent://scan/#Intent;end', false),
      ('/relative/path.pdf', false),
      ('notice.pdf', false),
      ('https://', false),
      ('https://localhost/x', false),
      ('mailto:someone@example.com', false),
      ('', false),
      (null, false),
      (42, false),
    ];
    for (final (v, ok) in cases) {
      test('$v', () => expect(readUrl(v) != null, ok));
    }
  });

  group('isValidPostId', () {
    final cases = <(Object?, bool)>[
      ('ssc-cgl-2026-notice', true),
      ('a', true),
      ('0-start-digit', true),
      ('rrb-ntpc-2026', true),
      ('x' * 120, true),
      ('x' * 121, false),
      ('-leading-dash', false),
      ('Upper-Case', false),
      ('with space', false),
      ('under_score', false),
      ('dots.in.id', false),
      ('../../etc/passwd', false),
      ('slash/inside', false),
      ('हिंदी', false),
      ('', false),
      (null, false),
      (5, false),
    ];
    for (final (v, ok) in cases) {
      test('$v', () => expect(isValidPostId(v), ok));
    }
  });

  group('readInstant', () {
    test('ISO with Z', () => expect(readInstant('2026-10-07T09:12:00Z'), DateTime.utc(2026, 10, 7, 9, 12)));
    test('with offset is converted to UTC',
        () => expect(readInstant('2026-10-07T14:42:00+05:30'), DateTime.utc(2026, 10, 7, 9, 12)));
    test('always UTC', () => expect(readInstant('2026-10-07T09:12:00Z')!.isUtc, isTrue));
    test('garbage is null', () => expect(readInstant('yesterday'), isNull));
    test('numbers are null', () => expect(readInstant(1700000000), isNull));
    test('absurd years are null', () => expect(readInstant('1970-01-01T00:00:00Z'), isNull));
  });

  group('readStrings', () {
    test('dedupes, skips non-strings and keeps order', () {
      expect(readStrings(['b', 'a', 3, null, 'b', ' c ']), ['b', 'a', 'c']);
    });
    test('lower-cases on request', () {
      expect(readStrings(['Central-Govt', 'central-govt'], lower: true), ['central-govt']);
    });
    test('non-list is empty', () => expect(readStrings('central-govt'), isEmpty));
  });

  group('readMap / readList / readBool', () {
    test('readMap drops non-string keys', () {
      expect(readMap({1: 'a', 'b': 2}), {'b': 2});
    });
    test('readMap of non-map is null', () => expect(readMap([1]), isNull));
    test('readList of non-list is empty', () => expect(readList('x'), isEmpty));
    test('readBool only accepts booleans', () {
      expect(readBool(true), isTrue);
      expect(readBool('yes'), isFalse);
      expect(readBool(null, fallback: true), isTrue);
    });
  });

  group('LocalText', () {
    test('parses en and hi', () {
      final t = LocalText.tryParse({'en': 'Hello', 'hi': 'नमस्ते'})!;
      expect(t.of(AppLang.en), 'Hello');
      expect(t.of(AppLang.hi), 'नमस्ते');
    });
    test('missing Hindi falls back to English', () {
      expect(LocalText.tryParse({'en': 'Only English'})!.of(AppLang.hi), 'Only English');
    });
    test('missing English falls back to Hindi', () {
      expect(LocalText.tryParse({'hi': 'केवल हिंदी'})!.of(AppLang.en), 'केवल हिंदी');
    });
    test('plain string is used for both', () {
      final t = LocalText.tryParse(' ₹100 ')!;
      expect((t.en, t.hi), ('₹100', '₹100'));
    });
    test('non-string values inside are ignored', () {
      expect(LocalText.tryParse({'en': 5, 'hi': 'ठीक'})!.of(AppLang.en), 'ठीक');
    });
    for (final bad in <Object?>[null, '', '   ', 5, [], {}, {'en': '', 'hi': ' '}, {'fr': 'Bonjour'}]) {
      test('no usable text: $bad', () => expect(LocalText.tryParse(bad), isNull));
    }
    test('equality', () {
      expect(const LocalText('a', 'b'), const LocalText('a', 'b'));
      expect(const LocalText('a', 'b') == const LocalText('a', 'c'), isFalse);
    });
    test('toJson round trip', () {
      const t = LocalText('a', 'ब');
      expect(LocalText.tryParse(t.toJson()), t);
    });
  });

  group('AppLang.tryParse', () {
    test('en', () => expect(AppLang.tryParse('en'), AppLang.en));
    test('hi', () => expect(AppLang.tryParse('hi'), AppLang.hi));
    test('unknown', () => expect(AppLang.tryParse('fr'), isNull));
    test('null', () => expect(AppLang.tryParse(null), isNull));
  });
}
