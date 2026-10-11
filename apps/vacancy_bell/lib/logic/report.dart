/// "Report a mistake": validation, local rate limit and the database entry.
library;

import 'dart:convert';

import '../config.dart';
import '../core/json_read.dart';
import '../data/kv_store.dart';

enum ReportReason {
  wrongDate('wrong_date'),
  wrongFee('wrong_fee'),
  wrongEligibility('wrong_eligibility'),
  brokenLink('broken_link'),
  other('other');

  const ReportReason(this.wire);
  final String wire;

  static ReportReason? tryParse(Object? v) {
    for (final r in values) {
      if (r.wire == v) return r;
    }
    return null;
  }
}

const maxReportNote = 300;
const maxReportsPerDay = 10;

enum ReportProblem { badItem, noteTooLong, noteNeeded }

class ReportDraft {
  const ReportDraft({required this.item, required this.reason, this.note = ''});
  final String item;
  final ReportReason reason;
  final String note;

  /// Cleaned note: control characters removed, spaces trimmed.
  String get cleanNote => cleanText(note);

  /// Null when the draft can be sent.
  ReportProblem? get problem {
    if (!isValidPostId(item)) return ReportProblem.badItem;
    final n = cleanNote;
    if (n.length > maxReportNote) return ReportProblem.noteTooLong;
    // "Other" without a word of explanation is not actionable.
    if (reason == ReportReason.other && n.isEmpty) return ReportProblem.noteNeeded;
    return null;
  }

  /// The `feedReports/<push id>` value from SCHEMA.md. [at] is the server
  /// timestamp placeholder supplied by the backend.
  Map<String, Object?> toEntry({required String uid, required Object at}) => {
        'app': AppConfig.reportAppId,
        'item': item,
        'reason': reason.wire,
        'note': cleanNote,
        'by': uid,
        'at': at,
      };
}

/// Remembers when reports were sent, on the phone, to stop accidental
/// floods: at most [maxReportsPerDay] in 24 hours and one per post and
/// reason.
class ReportLimiter {
  ReportLimiter(this._store, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final DateTime Function() _clock;
  static const _key = 'reportLog';
  static const window = Duration(hours: 24);

  List<(int, String)> _read() {
    final raw = _store.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final out = <(int, String)>[];
      for (final e in list) {
        if (e is Map && e['t'] is int && e['k'] is String) {
          out.add((e['t'] as int, e['k'] as String));
        }
      }
      return out;
    } on FormatException {
      return [];
    }
  }

  List<(int, String)> _recent() {
    final since = _clock().subtract(window).millisecondsSinceEpoch;
    return _read().where((e) => e.$1 > since).toList();
  }

  static String keyOf(ReportDraft d) => '${d.item}|${d.reason.wire}';

  int get sentToday => _recent().length;

  bool get limitReached => sentToday >= maxReportsPerDay;

  bool alreadySent(ReportDraft d) =>
      _recent().any((e) => e.$2 == keyOf(d));

  Future<void> record(ReportDraft d) async {
    final list = _recent()..add((_clock().millisecondsSinceEpoch, keyOf(d)));
    await _store.setString(
        _key, jsonEncode([for (final e in list) {'t': e.$1, 'k': e.$2}]));
  }
}

enum ReportOutcome { sent, invalid, duplicate, rateLimited, failed }

/// Where reports go. The Firebase one is in data/report_backend.dart; tests
/// use a fake.
abstract class ReportBackend {
  /// Signs in if needed and writes [draft]. Throws on failure.
  Future<void> send(ReportDraft draft);
}

class ReportService {
  ReportService(this.backend, this.limiter);
  final ReportBackend backend;
  final ReportLimiter limiter;

  Future<ReportOutcome> submit(ReportDraft draft) async {
    if (draft.problem != null) return ReportOutcome.invalid;
    if (limiter.alreadySent(draft)) return ReportOutcome.duplicate;
    if (limiter.limitReached) return ReportOutcome.rateLimited;
    try {
      await backend.send(draft);
    } catch (_) {
      return ReportOutcome.failed;
    }
    await limiter.record(draft);
    return ReportOutcome.sent;
  }
}
