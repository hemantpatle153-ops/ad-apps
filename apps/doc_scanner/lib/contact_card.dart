/// Contact details read from a business card photo (OCR text).
class ContactCard {
  ContactCard({
    this.name = '',
    this.company = '',
    this.phones = const [],
    this.emails = const [],
    this.websites = const [],
  });

  final String name;
  final String company;
  final List<String> phones;
  final List<String> emails;
  final List<String> websites;

  bool get isEmpty =>
      name.isEmpty && phones.isEmpty && emails.isEmpty && websites.isEmpty;

  static final _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
  static final _web = RegExp(
      r'\b((https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|in|org|net|io|co|biz|info|app|dev)(/\S*)?)\b',
      caseSensitive: false);
  static final _phone = RegExp(r'(\+?\d[\d\s().-]{7,}\d)');
  static final _companyWords = RegExp(
      r'\b(pvt|ltd|llp|inc|llc|limited|corp|company|co\.|technologies|solutions|services|enterprises|industries|group)\b',
      caseSensitive: false);

  factory ContactCard.parse(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final emails = <String>{};
    final phones = <String>{};
    final webs = <String>{};
    var name = '';
    var company = '';
    for (final l in lines) {
      for (final m in _email.allMatches(l)) {
        emails.add(m.group(0)!);
      }
      final noEmail = l.replaceAll(_email, ' ');
      for (final m in _phone.allMatches(noEmail)) {
        final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= 8 && digits.length <= 15) {
          phones.add(m.group(0)!.trim());
        }
      }
      for (final m in _web.allMatches(noEmail)) {
        webs.add(m.group(1)!);
      }
    }
    for (final l in lines) {
      final hasContact = _email.hasMatch(l) ||
          _web.hasMatch(l) ||
          RegExp(r'\d{4,}').hasMatch(l);
      if (hasContact) continue;
      if (company.isEmpty && _companyWords.hasMatch(l)) {
        company = l;
        continue;
      }
      // A name is short, mostly letters, two to four words.
      final words = l.split(RegExp(r'\s+'));
      if (name.isEmpty &&
          words.length >= 2 &&
          words.length <= 4 &&
          RegExp(r"^[A-Za-z .'-]+$").hasMatch(l)) {
        name = l;
      }
    }
    return ContactCard(
      name: name,
      company: company,
      phones: phones.toList(),
      emails: emails.toList(),
      websites: webs.toList(),
    );
  }

  static String _esc(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;')
      .replaceAll('\n', r'\n');

  /// vCard 3.0 that phones' contacts apps can import.
  String toVCard() {
    final b = StringBuffer('BEGIN:VCARD\r\nVERSION:3.0\r\n');
    final n = name.isEmpty ? (company.isEmpty ? 'Contact' : company) : name;
    final parts = n.split(' ');
    final last = parts.length > 1 ? parts.last : '';
    final first =
        parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : n;
    b.write('N:${_esc(last)};${_esc(first)};;;\r\n');
    b.write('FN:${_esc(n)}\r\n');
    if (company.isNotEmpty) b.write('ORG:${_esc(company)}\r\n');
    for (final p in phones) {
      b.write('TEL;TYPE=CELL:${p.replaceAll(RegExp(r'[^\d+]'), '')}\r\n');
    }
    for (final e in emails) {
      b.write('EMAIL:$e\r\n');
    }
    for (final w in websites) {
      b.write('URL:$w\r\n');
    }
    b.write('END:VCARD\r\n');
    return b.toString();
  }
}
