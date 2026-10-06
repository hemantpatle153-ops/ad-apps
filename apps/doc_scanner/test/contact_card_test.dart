import 'package:doc_scanner/contact_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = '''
Priya Sharma
Senior Designer
Brightline Technologies Pvt Ltd
+91 98765 43210
priya.sharma@brightline.in
www.brightline.in
''';

  test('reads name, company, phone, email and website', () {
    final c = ContactCard.parse(sample);
    expect(c.name, 'Priya Sharma');
    expect(c.company, 'Brightline Technologies Pvt Ltd');
    expect(c.phones, ['+91 98765 43210']);
    expect(c.emails, ['priya.sharma@brightline.in']);
    expect(c.websites, contains('www.brightline.in'));
  });

  test('the email domain is not taken as a website', () {
    final c = ContactCard.parse('Ravi Kumar\nravi@shop.com');
    expect(c.websites, isEmpty);
  });

  test('short numbers are not phones', () {
    expect(ContactCard.parse('Office 1204, Floor 3').phones, isEmpty);
  });

  test('empty text gives an empty card', () {
    expect(ContactCard.parse('').isEmpty, isTrue);
  });

  test('vCard contains every field and escapes commas', () {
    final v = ContactCard.parse(sample).toVCard();
    expect(v, startsWith('BEGIN:VCARD'));
    expect(v, contains('FN:Priya Sharma'));
    expect(v, contains('N:Sharma;Priya;;;'));
    expect(v, contains('TEL;TYPE=CELL:+919876543210'));
    expect(v, contains('EMAIL:priya.sharma@brightline.in'));
    expect(v.trim(), endsWith('END:VCARD'));
    final esc = ContactCard(name: 'A B', company: 'X, Y').toVCard();
    expect(esc, contains(r'ORG:X\, Y'));
  });
}
