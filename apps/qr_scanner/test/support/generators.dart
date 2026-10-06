import 'dart:math';

/// Every upper/lower case spelling of [s] (letters only are toggled).
List<String> casePermutations(String s) {
  var out = <String>[''];
  for (final ch in s.split('')) {
    final lo = ch.toLowerCase();
    final up = ch.toUpperCase();
    out = [
      for (final p in out) ...{'$p$lo', '$p$up'},
    ];
  }
  return out.toSet().toList();
}

/// Distinct random ASCII digit strings of exactly [length] characters.
List<String> randomDigits(Random r, int length, int count) {
  final out = <String>{};
  while (out.length < count) {
    out.add(List.generate(length, (_) => r.nextInt(10)).join());
  }
  return out.toList();
}

const _alpha = 'abcdefghijklmnopqrstuvwxyz';

String randomWord(Random r, int minLen, int maxLen) {
  final len = minLen + r.nextInt(maxLen - minLen + 1);
  return List.generate(len, (_) => _alpha[r.nextInt(_alpha.length)]).join();
}

/// Well-formed http(s) URLs with lowercase scheme and host.
List<String> sampleUrls() {
  const schemes = ['http', 'https'];
  const hosts = [
    'example.com',
    'www.google.com',
    'sub.domain.co.in',
    'localhost:8080',
    '192.168.1.1',
    'shop.example.org',
  ];
  const paths = [
    '',
    '/',
    '/a/b/c',
    '/search?q=qr',
    '/p?id=42&ref=scan',
    '/menu#drinks',
  ];
  return [
    for (final s in schemes)
      for (final h in hosts)
        for (final p in paths) '$s://$h$p',
  ];
}

/// UPI payment links paired with the payee address they carry.
List<(String, String)> sampleUpi(Random r, int count) {
  const banks = ['okicici', 'oksbi', 'ybl', 'paytm', 'okhdfcbank', 'upi'];
  final out = <String, String>{};
  while (out.length < count) {
    final pa = '${randomWord(r, 3, 10)}@${banks[r.nextInt(banks.length)]}';
    final name = '${randomWord(r, 3, 8)}%20${randomWord(r, 3, 8)}';
    final amount = '${r.nextInt(5000)}.${r.nextInt(90) + 10}';
    final link = switch (r.nextInt(3)) {
      0 => 'upi://pay?pa=$pa',
      1 => 'upi://pay?pa=$pa&pn=$name',
      _ => 'upi://pay?pa=$pa&pn=$name&am=$amount&cu=INR',
    };
    out[link] = pa;
  }
  return [for (final e in out.entries) (e.key, e.value)];
}

List<String> sampleWifi(Random r, int count) {
  const types = ['WPA', 'WEP', 'nopass', 'WPA2'];
  final out = <String>{};
  while (out.length < count) {
    final ssid = randomWord(r, 2, 12);
    final t = types[r.nextInt(types.length)];
    final pass = t == 'nopass' ? '' : randomWord(r, 8, 16);
    final hidden = r.nextBool() ? 'H:true;' : '';
    out.add('WIFI:S:$ssid;T:$t;P:$pass;$hidden;');
  }
  return out.toList();
}

/// tel: links paired with the number they carry.
List<(String, String)> samplePhones(Random r, int count) {
  final out = <String, String>{};
  while (out.length < count) {
    final digits = List.generate(6 + r.nextInt(7), (_) => r.nextInt(10)).join();
    final number = switch (r.nextInt(3)) {
      0 => digits,
      1 => '+$digits',
      _ => '${digits.substring(0, 3)}-${digits.substring(3)}',
    };
    out['tel:$number'] = number;
  }
  return [for (final e in out.entries) (e.key, e.value)];
}

/// mailto: links paired with the address they carry.
List<(String, String)> sampleEmails(Random r, int count) {
  const domains = ['gmail.com', 'example.org', 'mail.co.in', 'corp.io'];
  final out = <String, String>{};
  while (out.length < count) {
    final addr = '${randomWord(r, 2, 10)}@${domains[r.nextInt(domains.length)]}';
    final link = r.nextBool()
        ? 'mailto:$addr'
        : 'mailto:$addr?subject=${randomWord(r, 3, 9)}';
    out[link] = addr;
  }
  return [for (final e in out.entries) (e.key, e.value)];
}
