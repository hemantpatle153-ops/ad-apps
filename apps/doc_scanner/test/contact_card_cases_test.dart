import 'dart:math';

import 'package:doc_scanner/contact_card.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads one vCard property value (unescaped) for checks.
List<String> prop(String vcard, String key) => [
      for (final l in vcard.split('\r\n'))
        if (l.startsWith('$key:')) l.substring(key.length + 1)
    ];

void main() {
  group('emails', () {
    const emails = [
      'a@b.co',
      'priya.sharma@brightline.in',
      'first+tag@mail.example.com',
      'x_y-z@sub-domain.org',
      'ravi123@shop.io',
      'HELLO@CAPS.COM',
      'name.surname@company.co.in',
      'info@my-startup.dev',
    ];
    for (final e in emails) {
      test('finds $e', () {
        final c = ContactCard.parse('Ravi Kumar\nEmail: $e');
        expect(c.emails, [e]);
        expect(c.name, 'Ravi Kumar');
      });
    }
    test('two emails on one line are both found', () {
      expect(ContactCard.parse('a@x.com / b@y.org').emails, ['a@x.com', 'b@y.org']);
    });
    test('repeated emails are kept once', () {
      expect(ContactCard.parse('a@x.com\na@x.com').emails, ['a@x.com']);
    });
    for (final s in ['no at sign here', 'user@localhost', '@nouser.com x']) {
      test('"$s" has no full email', () {
        final c = ContactCard.parse(s);
        expect(c.emails.where((e) => e.startsWith('@')), isEmpty);
        if (!s.contains('.')) expect(c.emails, isEmpty);
      });
    }
  });

  group('phones', () {
    const phones = {
      '+91 98765 43210': '+919876543210',
      '98765 43210': '9876543210',
      '+1 (415) 555-0132': '+14155550132',
      '022-2345-6789': '02223456789',
      '+44 20 7946 0958': '+442079460958',
      '080.4123.4567': '08041234567',
      '9876543210': '9876543210',
      '+971 4 123 4567': '+97141234567',
      '1800 123 4567': '18001234567',
      '(011) 2345 6789': '01123456789',
    };
    phones.forEach((raw, tel) {
      test('finds $raw', () {
        final c = ContactCard.parse('Asha Rao\nMob: $raw');
        expect(c.phones.length, 1);
        expect(c.phones.single.replaceAll(RegExp(r'[^\d+]'), ''), tel);
        expect(c.toVCard(), contains('TEL;TYPE=CELL:$tel\r\n'));
      });
    });
    for (final s in ['Room 12', 'Office 1204, Floor 3', 'PIN 560001', 'Year 2024', '12-34']) {
      test('"$s" is not a phone', () {
        expect(ContactCard.parse(s).phones, isEmpty);
      });
    }
    test('more than 15 digits is not a phone', () {
      expect(ContactCard.parse('1234567890123456789').phones, isEmpty);
    });
    test('two phones on separate lines', () {
      final c = ContactCard.parse('T: 98765 43210\nM: 91234 56789');
      expect(c.phones, ['98765 43210', '91234 56789']);
    });
    test('digits inside an email are not a phone', () {
      expect(ContactCard.parse('user9876543210@mail.com').phones, isEmpty);
    });
  });

  group('websites', () {
    const sites = [
      'www.brightline.in',
      'https://example.com',
      'http://shop.example.org/contact',
      'acme.io',
      'my-site.net',
      'portfolio.dev',
      'www.store.co',
      'tools.app',
      'example.biz',
      'help.info',
    ];
    for (final w in sites) {
      test('finds $w', () {
        final c = ContactCard.parse('Neha Gupta\n$w');
        expect(c.websites, contains(w));
        expect(c.toVCard(), contains('URL:'));
      });
    }
    for (final s in ['priya@brightline.in', 'contact@acme.io']) {
      test('email domain in "$s" is not a website', () {
        expect(ContactCard.parse(s).websites, isEmpty);
      });
    }
    test('unknown endings are not websites', () {
      expect(ContactCard.parse('file.txt notes.pdf').websites, isEmpty);
    });
  });

  group('names', () {
    const names = [
      'Priya Sharma',
      'Ravi Kumar Singh',
      "Sean O'Brien",
      'Mary-Jane Watson',
      'Dr. A. P. J',
      'Anil K Mehta',
    ];
    for (final n in names) {
      test('"$n" is a name', () {
        expect(ContactCard.parse('$n\n98765 43210').name, n);
      });
    }
    const notNames = [
      'Madonna',
      'Chief Technology Officer At Large Firm',
      'Flat 4B, MG Road',
      'Call 2024 now',
      'Ravi @ home',
    ];
    for (final n in notNames) {
      test('"$n" is not a name', () {
        expect(ContactCard.parse(n).name, isEmpty);
      });
    }
    test('first name-like line wins', () {
      expect(ContactCard.parse('Priya Sharma\nSenior Designer').name, 'Priya Sharma');
    });
    test('lines are trimmed', () {
      expect(ContactCard.parse('   Priya Sharma   ').name, 'Priya Sharma');
    });
  });

  group('companies', () {
    const companies = [
      'Brightline Technologies Pvt Ltd',
      'Acme Inc',
      'Blue Sky LLP',
      'Sharma Enterprises',
      'Tata Consultancy Services',
      'Global Solutions',
      'Reliance Industries Limited',
      'Northwind Group',
      'Foo Corp',
      'Widget LLC',
    ];
    for (final co in companies) {
      test('"$co" is a company', () {
        final c = ContactCard.parse('Priya Sharma\n$co\npriya@x.com');
        expect(c.company, co);
        expect(c.name, 'Priya Sharma');
        expect(c.toVCard(), contains('ORG:$co\r\n'));
      });
    }
    test('company with a long number is skipped', () {
      expect(ContactCard.parse('Acme Inc 12345').company, isEmpty);
    });
  });

  group('isEmpty', () {
    test('default card is empty', () => expect(ContactCard().isEmpty, isTrue));
    test('company alone still counts as empty', () {
      expect(ContactCard(company: 'Acme Inc').isEmpty, isTrue);
    });
    test('name makes it non-empty', () => expect(ContactCard(name: 'A B').isEmpty, isFalse));
    test('phone makes it non-empty', () => expect(ContactCard(phones: ['1']).isEmpty, isFalse));
    test('email makes it non-empty', () => expect(ContactCard(emails: ['a@b.c']).isEmpty, isFalse));
    test('website makes it non-empty', () => expect(ContactCard(websites: ['a.com']).isEmpty, isFalse));
  });

  group('vCard N and FN', () {
    const cases = {
      'Priya Sharma': ('Sharma', 'Priya'),
      'Ravi Kumar Singh': ('Singh', 'Ravi Kumar'),
      'Madonna': ('', 'Madonna'),
      'A B C D': ('D', 'A B C'),
    };
    cases.forEach((name, nf) {
      test(name, () {
        final v = ContactCard(name: name).toVCard();
        expect(prop(v, 'N'), ['${nf.$1};${nf.$2};;;']);
        expect(prop(v, 'FN'), [name]);
      });
    });
    test('no name falls back to the company', () {
      final v = ContactCard(company: 'Acme Inc').toVCard();
      expect(prop(v, 'FN'), ['Acme Inc']);
      expect(prop(v, 'ORG'), ['Acme Inc']);
    });
    test('nothing at all is "Contact"', () {
      expect(prop(ContactCard().toVCard(), 'FN'), ['Contact']);
    });
  });

  group('vCard escaping', () {
    const cases = {
      'A, B': r'A\, B',
      'A;B': r'A\;B',
      r'A\B': r'A\\B',
      'A\nB': r'A\nB',
      r'x,;\': r'x\,\;\\',
    };
    cases.forEach((raw, esc) {
      test('company ${esc.replaceAll('\\', '/')}', () {
        expect(prop(ContactCard(name: 'Z Y', company: raw).toVCard(), 'ORG'), [esc]);
      });
    });
  });

  group('vCard structure', () {
    test('lines end with CRLF and wrap in BEGIN/END', () {
      final v = ContactCard(name: 'A B', phones: ['+1 2'], emails: ['e@x.io'], websites: ['x.io']).toVCard();
      final lines = v.split('\r\n');
      expect(lines.first, 'BEGIN:VCARD');
      expect(lines[1], 'VERSION:3.0');
      expect(lines[lines.length - 2], 'END:VCARD');
      expect(lines.last, '');
      expect(v.replaceAll('\r\n', '').contains('\n'), isFalse);
    });
    test('one TEL, EMAIL, URL line each per value', () {
      final v = ContactCard(
          name: 'A B',
          phones: ['111 222 3333', '+91 (98) 765'],
          emails: ['a@x.io', 'b@y.io'],
          websites: ['x.io', 'y.io', 'z.io']).toVCard();
      expect(prop(v, 'TEL;TYPE=CELL'), ['1112223333', '+9198765']);
      expect(prop(v, 'EMAIL'), ['a@x.io', 'b@y.io']);
      expect(prop(v, 'URL'), ['x.io', 'y.io', 'z.io']);
    });
  });

  group('generated cards round-trip through OCR text', () {
    const first = ['Priya', 'Ravi', 'Asha', 'John', 'Meera', 'Arjun', 'Lena', 'Omar'];
    const last = ['Sharma', 'Kumar', 'Rao', 'Smith', 'Iyer', 'Patel', 'Khan', 'Das'];
    const cos = ['Brightline Pvt Ltd', 'Acme Inc', 'Nova Solutions', 'Delta Group'];
    const tlds = ['com', 'in', 'io', 'org'];
    for (var seed = 0; seed < 40; seed++) {
      test('seed $seed', () {
        final r = Random(seed);
        final f = first[r.nextInt(first.length)];
        final l = last[r.nextInt(last.length)];
        final co = cos[r.nextInt(cos.length)];
        final dom = '${co.split(' ').first.toLowerCase()}.${tlds[r.nextInt(tlds.length)]}';
        final digits = List.generate(10, (_) => r.nextInt(10)).join();
        final phone = '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
        final email = '${f.toLowerCase()}.${l.toLowerCase()}@$dom';
        final lines = ['$f $l', 'Manager', co, phone, email, 'www.$dom']..shuffle(r);
        // Keep the name above the title so the title is not taken as name.
        lines.remove('$f $l');
        lines.insert(0, '$f $l');
        final c = ContactCard.parse(lines.join('\n'));
        expect(c.name, '$f $l');
        expect(c.company, co);
        expect(c.phones, [phone]);
        expect(c.emails, [email]);
        expect(c.websites, contains('www.$dom'));
        final v = c.toVCard();
        expect(prop(v, 'N'), ['$l;$f;;;']);
        expect(prop(v, 'TEL;TYPE=CELL'), ['+91$digits']);
      });
    }
  });
}
