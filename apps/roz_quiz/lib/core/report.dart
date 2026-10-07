/// "Report a mistake" for a question, written to Firebase `feedReports`
/// (see SCHEMA.md, Reports).
enum ReportReason {
  wrongAnswer('wrong_answer'),
  wrongQuestion('wrong_question'),
  translation('other'),
  other('other');

  const ReportReason(this.wire);

  /// The value of `reason` in the database; the schema has no translation
  /// reason, so it is sent as `other` with a "[translation]" note prefix.
  final String wire;
}

const kReportNoteMax = 300;
const kTranslationPrefix = '[translation] ';

enum ReportProblem {
  missingItem,
  noteTooLong,
  noteRequired,
  tooSoon,
  dailyLimit,
  alreadyReported,
}

/// What goes to the database (plus `at`, the server timestamp).
class ReportPayload {
  const ReportPayload({
    required this.item,
    required this.reason,
    required this.note,
    required this.by,
  });
  final String item;
  final String reason;
  final String note;
  final String by;

  Map<String, Object> toJson() =>
      {'app': 'roz_quiz', 'item': item, 'reason': reason, 'note': note, 'by': by};
}

/// The note as stored: trimmed, inner whitespace runs kept, at most
/// [kReportNoteMax] characters including the translation prefix.
String reportNote(ReportReason reason, String note) {
  var n = note.trim();
  if (reason == ReportReason.translation) n = '$kTranslationPrefix$n'.trim();
  final runes = n.runes.toList();
  if (runes.length > kReportNoteMax) {
    n = String.fromCharCodes(runes.take(kReportNoteMax)).trimRight();
  }
  return n;
}

/// Checks a report before sending. Null when it is fine.
ReportProblem? validateReport({
  required String item,
  required ReportReason reason,
  required String note,
}) {
  if (item.trim().isEmpty) return ReportProblem.missingItem;
  final n = note.trim();
  if (n.runes.length > kReportNoteMax) return ReportProblem.noteTooLong;
  if ((reason == ReportReason.other || reason == ReportReason.translation) &&
      n.runes.length < 5) {
    return ReportProblem.noteRequired;
  }
  return null;
}

/// Keeps one phone from flooding the report inbox: at most [perDay]
/// reports in any 24 hours, [minGap] between two, and one report per
/// question per [itemWindow].
class ReportRateLimiter {
  ReportRateLimiter({
    List<(String, DateTime)> history = const [],
    this.perDay = 10,
    this.minGap = const Duration(seconds: 20),
    this.itemWindow = const Duration(days: 30),
  }) : _history = [...history];

  final int perDay;
  final Duration minGap;
  final Duration itemWindow;
  final List<(String, DateTime)> _history;

  List<(String, DateTime)> get history => List.unmodifiable(_history);

  ReportProblem? check(String item, DateTime now) {
    _forget(now);
    for (final (id, at) in _history) {
      if (id == item && now.difference(at) < itemWindow) {
        return ReportProblem.alreadyReported;
      }
    }
    final recent = _history
        .where((e) => now.difference(e.$2) < const Duration(hours: 24))
        .toList();
    if (recent.length >= perDay) return ReportProblem.dailyLimit;
    // A clock set back makes "last" lie in the future; don't lock out.
    for (final (_, at) in _history) {
      final gap = now.difference(at);
      if (!gap.isNegative && gap < minGap) return ReportProblem.tooSoon;
    }
    return null;
  }

  void record(String item, DateTime now) {
    _history.add((item, now));
    _forget(now);
  }

  void _forget(DateTime now) {
    final keep = itemWindow > const Duration(hours: 24)
        ? itemWindow
        : const Duration(hours: 24);
    _history.removeWhere((e) => now.difference(e.$2) > keep);
  }

  List<List<Object>> toJson() => [
        for (final (id, at) in _history) [id, at.toUtc().millisecondsSinceEpoch]
      ];

  static List<(String, DateTime)> historyFromJson(Object? json) {
    if (json is! List) return const [];
    return [
      for (final e in json)
        if (e is List && e.length == 2 && e[0] is String && e[1] is int)
          (e[0] as String,
              DateTime.fromMillisecondsSinceEpoch(e[1] as int, isUtc: true))
    ];
  }
}

/// Where reports go. [FirebaseReportSink] in the app; a fake in tests.
abstract class ReportSink {
  /// Signs in if needed and returns the user id that goes into `by`.
  Future<String> signIn();

  Future<void> send(ReportPayload payload);
}

class ReportException implements Exception {
  const ReportException(this.problem, [this.cause]);
  final ReportProblem? problem;
  final Object? cause;

  /// A network or server failure rather than a rule.
  bool get offline => problem == null;

  @override
  String toString() => 'ReportException($problem, $cause)';
}

/// Validates, rate-limits and sends reports.
class ReportService {
  ReportService(this.sink, this.limiter, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final ReportSink sink;
  final ReportRateLimiter limiter;
  final DateTime Function() _clock;

  /// Problem that would stop a report for [item] right now, if any.
  ReportProblem? precheck(String item) => limiter.check(item, _clock());

  Future<void> submit({
    required String item,
    required ReportReason reason,
    required String note,
  }) async {
    final invalid = validateReport(item: item, reason: reason, note: note);
    if (invalid != null) throw ReportException(invalid);
    final limited = limiter.check(item, _clock());
    if (limited != null) throw ReportException(limited);
    try {
      final uid = await sink.signIn();
      await sink.send(ReportPayload(
        item: item.trim(),
        reason: reason.wire,
        note: reportNote(reason, note),
        by: uid,
      ));
    } catch (e) {
      throw ReportException(null, e);
    }
    limiter.record(item, _clock());
  }
}
