import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/src/scan_kind.dart';

import 'support/generators.dart';

String _show(String s) => s
    .replaceAll('\n', r'\n')
    .replaceAll('\t', r'\t')
    .replaceAll('\r', r'\r')
    .replaceAll(' ', '<nbsp>')
    .replaceAll(' ', '<emsp>')
    .replaceAll('﻿', '<bom>');

void main() {
  test('classifies common QR contents', () {
    expect(ScanKind.of('upi://pay?pa=shop@okicici&pn=Shop'), ScanKind.upi);
    expect(ScanKind.of('https://example.com'), ScanKind.url);
    expect(ScanKind.of('WIFI:S:Home;T:WPA;P:secret;;'), ScanKind.wifi);
    expect(ScanKind.of('8901030865278'), ScanKind.product);
    expect(ScanKind.of('hello world'), ScanKind.text);
  });

  test('only offers to open things another app can handle', () {
    expect(ScanKind.launchUri('hello world'), isNull);
    expect(ScanKind.launchUri('WIFI:S:Home;;'), isNull);
    expect(ScanKind.launchUri('https://example.com').toString(),
        'https://example.com');
  });

  group('enum metadata', () {
    const expected = {
      ScanKind.url: (Icons.link, 'Link'),
      ScanKind.upi: (Icons.currency_rupee, 'UPI payment'),
      ScanKind.wifi: (Icons.wifi, 'Wi-Fi'),
      ScanKind.phone: (Icons.phone, 'Phone number'),
      ScanKind.email: (Icons.email, 'Email'),
      ScanKind.text: (Icons.notes, 'Text'),
      ScanKind.product: (Icons.qr_code_2, 'Product code'),
    };
    test('has exactly ${expected.length} kinds', () {
      expect(ScanKind.values.toSet(), expected.keys.toSet());
    });
    for (final e in expected.entries) {
      test('${e.key.name} label is "${e.value.$2}"', () {
        expect(e.key.label, e.value.$2);
      });
      test('${e.key.name} icon', () {
        expect(e.key.icon, e.value.$1);
      });
    }
    test('labels are unique', () {
      final labels = ScanKind.values.map((k) => k.label).toList();
      expect(labels.toSet().length, labels.length);
    });
    test('icons are unique', () {
      final icons = ScanKind.values.map((k) => k.icon).toList();
      expect(icons.toSet().length, icons.length);
    });
  });

  group('prefix matching is case-insensitive', () {
    const prefixes = {
      'http://': ('example.com/x', ScanKind.url),
      'https://': ('example.com/y', ScanKind.url),
      'upi://': ('pay?pa=a@ybl', ScanKind.upi),
      'wifi:': ('S:Net;T:WPA;P:pw;;', ScanKind.wifi),
      'tel:': ('+911234567890', ScanKind.phone),
      'mailto:': ('me@example.com', ScanKind.email),
    };
    for (final p in prefixes.entries) {
      for (final spelling in casePermutations(p.key)) {
        final value = '$spelling${p.value.$1}';
        test('"$value" -> ${p.value.$2.name}', () {
          expect(ScanKind.of(value), p.value.$2);
        });
      }
    }
  });

  group('url', () {
    for (final url in sampleUrls()) {
      test('classifies $url as url', () {
        expect(ScanKind.of(url), ScanKind.url);
      });
      test('launchUri of $url is the same link', () {
        final uri = ScanKind.launchUri(url);
        expect(uri, isNotNull);
        expect(uri.toString(), url);
        expect(uri!.scheme, url.startsWith('https') ? 'https' : 'http');
      });
    }
  });

  group('upi', () {
    for (final (link, pa) in sampleUpi(Random(11), 40)) {
      test('classifies $link as upi', () {
        expect(ScanKind.of(link), ScanKind.upi);
      });
      test('launchUri of $link keeps payee $pa', () {
        final uri = ScanKind.launchUri(link)!;
        expect(uri.scheme, 'upi');
        expect(uri.host, 'pay');
        expect(uri.queryParameters['pa'], pa);
        expect(uri.toString(), link);
      });
    }
  });

  group('wifi', () {
    for (final w in sampleWifi(Random(12), 40)) {
      test('classifies $w as wifi', () {
        expect(ScanKind.of(w), ScanKind.wifi);
      });
      test('launchUri of $w is null', () {
        expect(ScanKind.launchUri(w), isNull);
      });
    }
  });

  group('phone', () {
    for (final (link, number) in samplePhones(Random(13), 40)) {
      test('classifies $link as phone', () {
        expect(ScanKind.of(link), ScanKind.phone);
      });
      test('launchUri of $link dials $number', () {
        final uri = ScanKind.launchUri(link)!;
        expect(uri.scheme, 'tel');
        expect(uri.path, number);
      });
    }
  });

  group('email', () {
    for (final (link, addr) in sampleEmails(Random(14), 40)) {
      test('classifies $link as email', () {
        expect(ScanKind.of(link), ScanKind.email);
      });
      test('launchUri of $link mails $addr', () {
        final uri = ScanKind.launchUri(link)!;
        expect(uri.scheme, 'mailto');
        expect(uri.path, addr);
        expect(uri.toString(), link);
      });
    }
  });

  group('product codes (8-14 ASCII digits)', () {
    final r = Random(15);
    for (var len = 8; len <= 14; len++) {
      for (final code in randomDigits(r, len, 10)) {
        test('classifies $code (len $len) as product', () {
          expect(ScanKind.of(code), ScanKind.product);
        });
        test('launchUri of $code is a Google search', () {
          final uri = ScanKind.launchUri(code)!;
          expect(uri.scheme, 'https');
          expect(uri.host, 'www.google.com');
          expect(uri.path, '/search');
          expect(uri.queryParameters, {'q': code});
        });
      }
    }
  });

  group('digit strings outside 8-14 are plain text', () {
    final r = Random(16);
    for (final len in [1, 2, 3, 4, 5, 6, 7, 15, 16, 18, 20, 25]) {
      for (final code in randomDigits(r, len, 3)) {
        test('classifies $code (len $len) as text', () {
          expect(ScanKind.of(code), ScanKind.text);
          expect(ScanKind.launchUri(code), isNull);
        });
      }
    }
  });

  group('plain text', () {
    final r = Random(17);
    final values = <String>{
      '',
      ' ',
      '\n\t',
      'hello',
      'www.example.com',
      'example.com/path',
      'ftp://files.example.com',
      'sms:+911234567890',
      'smsto:12345:hi',
      'geo:12.97,77.59',
      'BEGIN:VCARD\nFN:Jane\nEND:VCARD',
      'MECARD:N:Doe,John;;',
      'http:/example.com',
      'http//example.com',
      'https:example.com',
      'htp://example.com',
      'httpx://example.com',
      'upi:/pay?pa=a@b',
      'upi:pay?pa=a@b',
      'wifi',
      'wi-fi:S:x;;',
      'tel',
      'tel;123',
      'phone:123',
      'mailto',
      'mail:me@x.com',
      'me@example.com',
      '+919876543210',
      '1234 5678',
      '1234-5678',
      '12345678a',
      'a12345678',
      '12345.678',
      '1234567٨',
      '١٢٣٤٥٦٧٨٩',
      '１２３４５６７８',
      ' x https://example.com',
      'see https://example.com',
      'go to upi://pay',
      '"https://quoted.com"',
      'Lorem ipsum dolor sit amet',
      '🙂🙂🙂',
      'नमस्ते',
      '1.2.3.4',
      'javascript:alert(1)',
      'data:text/plain,hi',
      'file:///etc/hosts',
      'market://details?id=x',
      'intent://scan',
      'otpauth://totp/x?secret=y',
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT',
    };
    while (values.length < 110) {
      values.add('${randomWord(r, 1, 8)} ${randomWord(r, 1, 8)}');
    }
    for (final v in values) {
      test('classifies "${_show(v)}" as text', () {
        expect(ScanKind.of(v), ScanKind.text);
      });
      test('launchUri of "${_show(v)}" is null', () {
        expect(ScanKind.launchUri(v), isNull);
      });
    }
  });

  group('surrounding whitespace is ignored', () {
    const pads = [
      (' ', ' '),
      ('\n', '\n'),
      ('\t  ', ''),
      ('', '   \r\n'),
      (' ', ' '),
      ('﻿', ''),
    ];
    const bases = {
      'https://example.com/a': ScanKind.url,
      'http://x.org': ScanKind.url,
      'upi://pay?pa=x@ybl': ScanKind.upi,
      'WIFI:S:Home;T:WPA;P:pw;;': ScanKind.wifi,
      'tel:+911234567': ScanKind.phone,
      'mailto:me@example.com': ScanKind.email,
      '8901030865278': ScanKind.product,
      '12345678': ScanKind.product,
      'hello world': ScanKind.text,
      '1234567': ScanKind.text,
    };
    for (final b in bases.entries) {
      for (final (pre, post) in pads) {
        final v = '$pre${b.key}$post';
        test('"${_show(v)}" -> ${b.value.name}', () {
          expect(ScanKind.of(v), b.value);
        });
        test('launchUri("${_show(v)}") equals launchUri of trimmed value', () {
          expect(ScanKind.launchUri(v), ScanKind.launchUri(b.key));
        });
      }
    }
  });

  group('prefix precedence', () {
    const cases = {
      'upi://http://example.com': ScanKind.upi,
      'https://upi://pay': ScanKind.url,
      'http://wifi:S:x;;': ScanKind.url,
      'wifi:http://x.com': ScanKind.wifi,
      'wifi:tel:123': ScanKind.wifi,
      'tel:mailto:a@b.com': ScanKind.phone,
      'tel:12345678': ScanKind.phone,
      'mailto:tel:123': ScanKind.email,
      'mailto:12345678': ScanKind.email,
      'https://12345678': ScanKind.url,
      'upi://12345678': ScanKind.upi,
      'http://': ScanKind.url,
      'https://': ScanKind.url,
      'upi://': ScanKind.upi,
      'wifi:': ScanKind.wifi,
      'tel:': ScanKind.phone,
      'mailto:': ScanKind.email,
    };
    for (final c in cases.entries) {
      test('"${c.key}" -> ${c.value.name}', () {
        expect(ScanKind.of(c.key), c.value);
      });
    }
  });

  group('launchUri is non-null exactly for openable kinds', () {
    final r = Random(18);
    final samples = <String>[
      ...sampleUrls().take(6),
      ...sampleUpi(r, 4).map((e) => e.$1),
      ...sampleWifi(r, 4),
      ...samplePhones(r, 4).map((e) => e.$1),
      ...sampleEmails(r, 4).map((e) => e.$1),
      ...randomDigits(r, 13, 4),
      'plain words',
      'abc',
    ];
    const openable = {
      ScanKind.url,
      ScanKind.upi,
      ScanKind.phone,
      ScanKind.email,
      ScanKind.product,
    };
    for (final s in samples) {
      test('invariant holds for "$s"', () {
        final kind = ScanKind.of(s);
        expect(ScanKind.launchUri(s) != null, openable.contains(kind));
      });
    }
  });
}
