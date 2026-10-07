/// A calendar day in India Standard Time.
///
/// Everything date-based in the app (which daily quiz is "today", streaks,
/// reminders) uses IST, the same day the feed is published for, whatever
/// timezone the phone is set to. IST is UTC+05:30 all year (no daylight
/// saving), so the conversion is a fixed offset and all day arithmetic is
/// done on UTC dates, which never skip or repeat an hour.
class Day implements Comparable<Day> {
  /// Normalises out-of-range values, e.g. Day(2026, 1, 32) == Day(2026, 2, 1).
  factory Day(int year, int month, int day) {
    final d = DateTime.utc(year, month, day);
    return Day._(d.year, d.month, d.day);
  }

  const Day._(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static const istOffset = Duration(hours: 5, minutes: 30);
  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// The IST day that contains [instant].
  static Day ist(DateTime instant) {
    final t = instant.toUtc().add(istOffset);
    return Day._(t.year, t.month, t.day);
  }

  /// Day number counted from 1970-01-01 (negative before it).
  static Day fromIndex(int index) {
    final d = DateTime.utc(1970).add(Duration(days: index));
    return Day._(d.year, d.month, d.day);
  }

  /// Parses `YYYY-MM-DD`; null for anything else, including impossible
  /// dates such as 2026-02-30.
  static Day? tryParse(Object? s) {
    if (s is! String) return null;
    final m = _pattern.firstMatch(s.trim());
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final day = Day(y, mo, d);
    if (day.month != mo || day.day != d) return null;
    return day;
  }

  int get index =>
      DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  Day addDays(int n) => fromIndex(index + n);

  /// Whole days from [other] to this day (positive when this is later).
  int difference(Day other) => index - other.index;

  /// Monday = 1 ... Sunday = 7.
  int get weekday => DateTime.utc(year, month, day).weekday;

  /// The UTC instant when this IST day starts.
  DateTime get startUtc => DateTime.utc(year, month, day).subtract(istOffset);

  /// The UTC instant of [minutes] after IST midnight of this day.
  DateTime atIst(int minutes) => startUtc.add(Duration(minutes: minutes));

  String get key =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}'
      '-${day.toString().padLeft(2, '0')}';

  bool isBefore(Day o) => index < o.index;
  bool isAfter(Day o) => index > o.index;

  @override
  int compareTo(Day other) => index.compareTo(other.index);

  @override
  bool operator ==(Object other) =>
      other is Day &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => key;
}
