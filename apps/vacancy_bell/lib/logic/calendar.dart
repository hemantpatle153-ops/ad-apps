/// Exam calendar: upcoming important dates across posts, grouped by month.
library;

import '../core/json_read.dart';
import '../core/ymd.dart';
import '../models/post.dart';

enum CalendarKind { lastDate, exam, admitCard, result, other }

class CalendarEvent {
  const CalendarEvent({
    required this.date,
    required this.post,
    required this.label,
    required this.kind,
  });
  final Ymd date;
  final PostSummary post;

  /// The feed's label ("Exam date"); null for the post's last date.
  final LocalText? label;
  final CalendarKind kind;
}

class CalendarMonth {
  const CalendarMonth(this.year, this.month, this.events);
  final int year;
  final int month;
  final List<CalendarEvent> events;
}

CalendarKind kindOfLabel(LocalText label) {
  final s = label.en.toLowerCase();
  if (s.contains('last date') || s.contains('closing')) {
    return CalendarKind.lastDate;
  }
  if (s.contains('admit')) return CalendarKind.admitCard;
  if (s.contains('result')) return CalendarKind.result;
  if (s.contains('exam') || s.contains('test') || s.contains('cbt')) {
    return CalendarKind.exam;
  }
  return CalendarKind.other;
}

/// Events from [today] on (up to [maxEvents]), from every summary's last date
/// and from the important dates of any post detail we have.
List<CalendarEvent> buildCalendar(
  Iterable<PostSummary> posts,
  Map<String, PostDetail> details, {
  required Ymd today,
  int maxEvents = 500,
}) {
  final events = <CalendarEvent>[];
  final keys = <String>{};
  void add(CalendarEvent e) {
    if (e.date.isBefore(today)) return;
    final key = '${e.post.id}|${e.date}|${e.kind.name}';
    if (keys.add(key)) events.add(e);
  }

  for (final p in posts) {
    final d = details[p.id];
    if (p.lastDate != null) {
      add(CalendarEvent(
          date: p.lastDate!, post: p, label: null, kind: CalendarKind.lastDate));
    }
    if (d == null) continue;
    for (final entry in d.importantDates) {
      final date = entry.date;
      if (date == null) continue;
      final kind = kindOfLabel(entry.label);
      // Start dates are not useful on a calendar of things to do.
      final en = entry.label.en.toLowerCase();
      if (en.contains('start') || en.contains('begin')) continue;
      add(CalendarEvent(
          date: date, post: p, label: entry.label, kind: kind));
    }
  }
  events.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.post.id.compareTo(b.post.id);
  });
  return events.length > maxEvents ? events.sublist(0, maxEvents) : events;
}

/// Groups sorted [events] by month.
List<CalendarMonth> groupByMonth(List<CalendarEvent> events) {
  final out = <CalendarMonth>[];
  for (final e in events) {
    if (out.isEmpty ||
        out.last.year != e.date.year ||
        out.last.month != e.date.month) {
      out.add(CalendarMonth(e.date.year, e.date.month, []));
    }
    out.last.events.add(e);
  }
  return out;
}
