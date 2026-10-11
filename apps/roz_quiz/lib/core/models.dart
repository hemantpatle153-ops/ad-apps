import 'bi.dart';
import 'day.dart';

/// Subjects in the feed, in the order the app lists them.
const kSubjects = [
  'gk',
  'history',
  'polity',
  'geography',
  'economy',
  'science',
  'current_affairs',
  'maths',
  'reasoning',
  'english',
  'computer',
];

/// Exams in the feed, in the order the app lists them.
const kExams = [
  'ssc',
  'railway',
  'banking',
  'upsc',
  'state_psc',
  'defence',
  'teaching',
];

enum Difficulty {
  easy,
  medium,
  hard;

  static Difficulty parse(Object? v) => switch (v) {
        'easy' => Difficulty.easy,
        'hard' => Difficulty.hard,
        _ => Difficulty.medium,
      };
}

/// Where a fact comes from, e.g. PIB.
class SourceRef {
  const SourceRef(this.name, this.url);
  final String name;

  /// An http(s) link, or null when the feed gave none or a bad one.
  final String? url;

  static SourceRef? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final url = json['url'];
    final okName = name is String && name.trim().isNotEmpty;
    final okUrl = url is String && isWebUrl(url);
    if (!okName && !okUrl) return null;
    return SourceRef(okName ? name.trim() : Uri.parse(url as String).host,
        okUrl ? url.trim() : null);
  }

  Map<String, Object?> toJson() => {'name': name, 'url': url};
}

/// True for absolute http and https links only.
bool isWebUrl(String s) {
  final u = Uri.tryParse(s.trim());
  return u != null &&
      (u.scheme == 'https' || u.scheme == 'http') &&
      u.host.isNotEmpty;
}

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// One multiple-choice question.
class Question {
  const Question({
    required this.id,
    required this.q,
    required this.options,
    required this.answer,
    required this.explanation,
    required this.subject,
    this.exams = const [],
    this.difficulty = Difficulty.medium,
    this.source,
    this.asked,
  });

  final String id;
  final Bi q;
  final List<Bi> options;
  final int answer;

  /// Empty when the feed gave none.
  final Bi explanation;

  /// One of [kSubjects]; unknown subjects become `gk`.
  final String subject;

  /// Known exams only, see [kExams].
  final List<String> exams;
  final Difficulty difficulty;
  final SourceRef? source;

  /// Set only for real previous-year questions, e.g. "SSC CGL 2023".
  final String? asked;

  bool get isPyq => asked != null;

  bool isCorrect(int? choice) => choice == answer;

  static final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$');

  /// Parses one question, or returns null when it can't be shown safely:
  /// missing id or text, not exactly 4 options, duplicate options, an
  /// answer outside 0-3, or `"verified": false`. Unknown keys are ignored.
  static Question? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    if (id == null || !_idPattern.hasMatch(id)) return null;
    if (json['verified'] == false) return null;
    final q = Bi.tryParse(json['q']);
    if (q == null) return null;
    final rawOptions = json['options'];
    if (rawOptions is! List || rawOptions.length != 4) return null;
    final options = <Bi>[];
    for (final o in rawOptions) {
      final b = Bi.tryParse(o);
      if (b == null) return null;
      options.add(b);
    }
    // Two identical options would make the question ambiguous.
    for (final lang in Lang.values) {
      final seen = options.map((o) => o.of(lang).toLowerCase()).toSet();
      if (seen.length != 4) return null;
    }
    final a = json['answer'];
    final answer = a is int
        ? a
        : (a is double && a == a.roundToDouble() ? a.toInt() : null);
    if (answer == null || answer < 0 || answer > 3) return null;
    final subject = _str(json['subject'])?.toLowerCase();
    final exams = <String>[];
    final rawExams = json['exams'];
    if (rawExams is List) {
      for (final e in rawExams) {
        if (e is String && kExams.contains(e) && !exams.contains(e)) {
          exams.add(e);
        }
      }
    }
    return Question(
      id: id,
      q: q,
      options: List.unmodifiable(options),
      answer: answer,
      explanation: Bi.tryParse(json['explanation']) ?? const Bi('', ''),
      subject: kSubjects.contains(subject) ? subject! : 'gk',
      exams: List.unmodifiable(exams),
      difficulty: Difficulty.parse(json['difficulty']),
      source: SourceRef.tryParse(json['source']),
      asked: _str(json['asked']),
    );
  }

  /// Parses a list, skipping malformed entries and repeated ids.
  static List<Question> parseList(Object? json) {
    if (json is! List) return const [];
    final out = <Question>[];
    final ids = <String>{};
    for (final item in json) {
      final q = tryParse(item);
      if (q != null && ids.add(q.id)) out.add(q);
    }
    return out;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'q': q.toJson(),
        'options': [for (final o in options) o.toJson()],
        'answer': answer,
        'explanation': explanation.toJson(),
        'subject': subject,
        'exams': exams,
        'difficulty': difficulty.name,
        'source': source?.toJson(),
        'asked': asked,
        'verified': true,
      };

  @override
  bool operator ==(Object other) => other is Question && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// `quiz/daily/<date>.json`.
class DailyQuiz {
  const DailyQuiz({required this.date, this.title, required this.questions});
  final Day date;
  final Bi? title;
  final List<Question> questions;

  static DailyQuiz? tryParse(Object? json, {Day? expected}) {
    if (json is! Map) return null;
    final date = Day.tryParse(json['date']) ?? expected;
    if (date == null) return null;
    if (expected != null && date != expected) return null;
    final questions = Question.parseList(json['questions']);
    if (questions.isEmpty) return null;
    return DailyQuiz(
        date: date, title: Bi.tryParse(json['title']), questions: questions);
  }
}

/// One 60-word current affairs note.
class CaNote {
  const CaNote({
    required this.id,
    required this.title,
    required this.body,
    this.source,
    this.tags = const [],
  });
  final String id;
  final Bi title;
  final Bi body;
  final SourceRef? source;
  final List<String> tags;

  static CaNote? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    final title = Bi.tryParse(json['title']);
    final body = Bi.tryParse(json['body']);
    if (id == null || title == null || body == null) return null;
    final tags = json['tags'] is List
        ? [
            for (final t in json['tags'] as List)
              if (t is String && t.trim().isNotEmpty) t.trim()
          ]
        : const <String>[];
    return CaNote(
        id: id,
        title: title,
        body: body,
        source: SourceRef.tryParse(json['source']),
        tags: tags);
  }
}

/// `quiz/current_affairs/<date>.json`.
class CaDay {
  const CaDay({required this.date, required this.notes, required this.questions});
  final Day date;
  final List<CaNote> notes;
  final List<Question> questions;

  bool get isEmpty => notes.isEmpty && questions.isEmpty;

  static CaDay? tryParse(Object? json, {Day? expected}) {
    if (json is! Map) return null;
    final date = Day.tryParse(json['date']) ?? expected;
    if (date == null) return null;
    if (expected != null && date != expected) return null;
    final notes = <CaNote>[];
    final ids = <String>{};
    if (json['notes'] is List) {
      for (final n in json['notes'] as List) {
        final note = CaNote.tryParse(n);
        if (note != null && ids.add(note.id)) notes.add(note);
      }
    }
    final day = CaDay(
        date: date,
        notes: notes,
        questions: Question.parseList(json['questions']));
    return day.isEmpty ? null : day;
  }
}

/// One entry of `banks` in `quiz/index.json`.
class BankInfo {
  const BankInfo({
    required this.id,
    required this.title,
    required this.count,
    required this.file,
    this.updatedAt,
  });
  final String id;
  final Bi title;
  final int count;
  final String file;
  final DateTime? updatedAt;

  static final _filePattern = RegExp(r'^quiz/banks/[a-z0-9_-]+\.json$');

  static BankInfo? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    final file = _str(json['file']);
    if (id == null || file == null || !_filePattern.hasMatch(file)) {
      return null;
    }
    final count = json['count'];
    final updated = _str(json['updatedAt']);
    return BankInfo(
      id: id,
      title: Bi.tryParse(json['title']) ?? Bi.same(id),
      count: count is int && count >= 0 ? count : 0,
      file: file,
      updatedAt: updated == null ? null : DateTime.tryParse(updated)?.toUtc(),
    );
  }
}

/// `quiz/index.json`.
class FeedIndex {
  const FeedIndex({
    this.generatedAt,
    this.daily = const [],
    this.currentAffairs = const [],
    this.banks = const [],
  });
  final DateTime? generatedAt;

  /// Newest first.
  final List<Day> daily;

  /// Newest first.
  final List<Day> currentAffairs;
  final List<BankInfo> banks;

  static List<Day> _days(Object? v) {
    if (v is! List) return const [];
    final set = <Day>{};
    for (final s in v) {
      final d = Day.tryParse(s);
      if (d != null) set.add(d);
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  static FeedIndex? tryParse(Object? json) {
    if (json is! Map) return null;
    final banks = <BankInfo>[];
    final ids = <String>{};
    if (json['banks'] is List) {
      for (final b in json['banks'] as List) {
        final info = BankInfo.tryParse(b);
        if (info != null && ids.add(info.id)) banks.add(info);
      }
    }
    final gen = _str(json['generatedAt']);
    return FeedIndex(
      generatedAt: gen == null ? null : DateTime.tryParse(gen)?.toUtc(),
      daily: _days(json['daily']),
      currentAffairs: _days(json['currentAffairs']),
      banks: banks,
    );
  }
}

/// `quiz/banks/<subject>.json` (also the format of the bundled bank).
class QuestionBank {
  const QuestionBank({required this.subject, required this.questions});
  final String subject;
  final List<Question> questions;

  static QuestionBank? tryParse(Object? json) {
    if (json is! Map) return null;
    final questions = Question.parseList(json['questions']);
    final subject = _str(json['subject']) ?? '';
    return QuestionBank(subject: subject, questions: questions);
  }
}
