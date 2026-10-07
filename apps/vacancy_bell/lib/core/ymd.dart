/// Calendar dates and India Standard Time helpers.
///
/// The feed's dates are plain `YYYY-MM-DD` days in India time. India has no
/// daylight saving, so IST is always UTC+05:30; all arithmetic here runs on
/// UTC midnights so a phone's own time zone can never shift a day.
library;

const istOffset = Duration(hours: 5, minutes: 30);

/// A calendar day without a time or zone.
class Ymd implements Comparable<Ymd> {
  /// Builds a day; out-of-range parts roll over like [DateTime.utc].
  factory Ymd(int year, int month, int day) {
    final d = DateTime.utc(year, month, day);
    return Ymd._(d.year, d.month, d.day);
  }

  const Ymd._(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Parses a strict `YYYY-MM-DD` string. Returns null for anything else,
  /// including impossible dates such as 2026-02-30.
  static Ymd? tryParse(Object? value) {
    if (value is! String) return null;
    final m = _pattern.firstMatch(value.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (y < 1900 || y > 2200 || mo < 1 || mo > 12 || d < 1) return null;
    if (d > daysInMonth(y, mo)) return null;
    return Ymd._(y, mo, d);
  }

  /// The calendar day of [dt] as written on its own clock (local or UTC).
  factory Ymd.ofDateTime(DateTime dt) => Ymd._(dt.year, dt.month, dt.day);

  /// Today's date in India for the instant [now].
  factory Ymd.istOf(DateTime now) =>
      Ymd.ofDateTime(now.toUtc().add(istOffset));

  DateTime get utcMidnight => DateTime.utc(year, month, day);

  /// The instant this day's [hour]:[minute] happens in India.
  DateTime istInstant(int hour, [int minute = 0]) =>
      DateTime.utc(year, month, day, hour, minute).subtract(istOffset);

  Ymd addDays(int days) => Ymd(year, month, day + days);

  /// Whole days from this day to [other] (negative if [other] is earlier).
  int daysUntil(Ymd other) =>
      (other.utcMidnight.difference(utcMidnight).inHours / 24).round();

  bool isBefore(Ymd other) => compareTo(other) < 0;
  bool isAfter(Ymd other) => compareTo(other) > 0;

  /// Monday = 1 ... Sunday = 7.
  int get weekday => utcMidnight.weekday;

  @override
  int compareTo(Ymd other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is Ymd &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  static bool isLeapYear(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  static int daysInMonth(int y, int m) => switch (m) {
        2 => isLeapYear(y) ? 29 : 28,
        4 || 6 || 9 || 11 => 30,
        _ => 31,
      };
}

/// Exact age between two days, as written on certificates: whole years,
/// then months, then days.
class AgeSpan {
  const AgeSpan(this.years, this.months, this.days);
  final int years;
  final int months;
  final int days;

  /// Age on [on] of someone born on [birth]. Null if [on] is before [birth].
  ///
  /// Someone born on 29 February completes a year on 1 March in common
  /// years, which is how Indian recruitment notices count it.
  static AgeSpan? between(Ymd birth, Ymd on) {
    if (on.isBefore(birth)) return null;
    var years = on.year - birth.year;
    var months = on.month - birth.month;
    if (on.day < birth.day) months -= 1;
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    // The last "monthiversary" on or before [on]; a 31st falls back to the
    // month's last day.
    final total = birth.month - 1 + years * 12 + months;
    final y = birth.year + total ~/ 12;
    final m = total % 12 + 1;
    final d = birth.day > Ymd.daysInMonth(y, m) ? Ymd.daysInMonth(y, m) : birth.day;
    final days = Ymd(y, m, d).daysUntil(on);
    return AgeSpan(years, months, days);
  }

  /// Completed years on [on] (0 if [on] is before [birth]).
  static int completedYears(Ymd birth, Ymd on) {
    if (on.isBefore(birth)) return 0;
    var years = on.year - birth.year;
    if (on.month < birth.month ||
        (on.month == birth.month && on.day < birth.day)) {
      years -= 1;
    }
    return years;
  }

  int get totalMonths => years * 12 + months;

  @override
  bool operator ==(Object other) =>
      other is AgeSpan &&
      other.years == years &&
      other.months == months &&
      other.days == days;

  @override
  int get hashCode => Object.hash(years, months, days);

  @override
  String toString() => '${years}y ${months}m ${days}d';
}

/// How urgent a last date is, relative to today in India.
enum Urgency {
  /// No last date in the feed.
  unknown,

  /// The last date has passed.
  closed,

  /// Today is the last date.
  lastDay,

  /// 1 to 3 days left.
  urgent,

  /// 4 to 7 days left.
  soon,

  /// More than a week left.
  open,
}

class Deadline {
  const Deadline(this.urgency, this.daysLeft);

  /// Days from today to the last date (negative once closed), null if unknown.
  final int? daysLeft;
  final Urgency urgency;

  static const urgentDays = 3;

  static Deadline of(Ymd? lastDate, Ymd today) {
    if (lastDate == null) return const Deadline(Urgency.unknown, null);
    final left = today.daysUntil(lastDate);
    final u = left < 0
        ? Urgency.closed
        : left == 0
            ? Urgency.lastDay
            : left <= urgentDays
                ? Urgency.urgent
                : left <= 7
                    ? Urgency.soon
                    : Urgency.open;
    return Deadline(u, left);
  }

  bool get isClosed => urgency == Urgency.closed;

  /// Red styling: last day or up to three days left.
  bool get isUrgent => urgency == Urgency.lastDay || urgency == Urgency.urgent;
}

/// Whether [postedAt] falls on [today] in India ("New" badge).
bool isPostedToday(DateTime? postedAt, Ymd today) =>
    postedAt != null && Ymd.istOf(postedAt) == today;
