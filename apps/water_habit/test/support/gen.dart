import 'dart:math';

/// Independent oracle: parses "h:mm AM/PM" back into minutes after midnight.
int parseClock(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2}) (AM|PM)$').firstMatch(s);
  if (m == null) throw FormatException('bad clock', s);
  var h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final pm = m.group(3) == 'PM';
  if (h == 12) h = 0;
  if (pm) h += 12;
  return h * 60 + min;
}

/// Seeded random calendar dates between 1990 and 2060.
List<DateTime> randomDates(int seed, int count) {
  final r = Random(seed);
  final base = DateTime.utc(1990, 1, 1);
  return [
    for (var i = 0; i < count; i++)
      () {
        final u = base.add(Duration(days: r.nextInt(70 * 365)));
        return DateTime(u.year, u.month, u.day);
      }(),
  ];
}

/// Calendar date [n] days before [d], DST-safe.
DateTime daysBefore(DateTime d, int n) => DateTime(d.year, d.month, d.day - n);

String randomName(Random r) {
  const words = [
    'Walk', 'Read', 'Stretch', 'Meditate', 'Journal', 'Floss', 'Run',
    'Yoga', 'Pushups', 'Vitamins', 'Piano', 'Spanish', 'Café ☕', 'Sleep 8h',
  ];
  final n = 1 + r.nextInt(3);
  return [for (var i = 0; i < n; i++) words[r.nextInt(words.length)]]
      .join(' ');
}
