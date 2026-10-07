import '../core/json_read.dart';
import '../core/ymd.dart';
import 'taxonomy.dart';

/// One entry of `jobs/index.json` (SCHEMA.md "PostSummary").
///
/// [tryParse] returns null for an entry without a valid id or title; every
/// other field is optional and simply null/empty when missing or malformed.
class PostSummary {
  const PostSummary({
    required this.id,
    required this.type,
    required this.title,
    this.org = LocalText.empty,
    this.source,
    this.category = JobCategory.other,
    this.postedAt,
    this.updatedAt,
    this.lastDate,
    this.totalPosts,
    this.qualifications = const [],
    this.states = const [],
    this.ageMin,
    this.ageMax,
    this.salary,
    this.tags = const [],
    this.verified = false,
  });

  final String id;
  final PostType type;
  final LocalText title;
  final LocalText org;
  final String? source;
  final JobCategory category;
  final DateTime? postedAt;
  final DateTime? updatedAt;
  final Ymd? lastDate;
  final int? totalPosts;
  final List<Qualification> qualifications;

  /// [allStates] or state codes. Empty means the feed did not say.
  final List<String> states;
  final int? ageMin;
  final int? ageMax;
  final LocalText? salary;
  final List<String> tags;
  final bool verified;

  static PostSummary? tryParse(Object? json) {
    final m = readMap(json);
    if (m == null) return null;
    final id = m['id'];
    if (!isValidPostId(id)) return null;
    final title = LocalText.tryParse(m['title']);
    if (title == null) return null;

    final quals = <Qualification>[];
    for (final q in readList(m['qualifications'])) {
      final v = Qualification.tryParse(q);
      if (v != null && !quals.contains(v)) quals.add(v);
    }
    final states = <String>[];
    for (final s in readList(m['states'])) {
      final v = parseStateCode(s);
      if (v != null && !states.contains(v)) states.add(v);
    }
    // "all" with specific states is contradictory; "all" wins.
    if (states.contains(allStates)) {
      states
        ..clear()
        ..add(allStates);
    }

    var ageMin = readInt(m['ageMin'], min: 10, max: 80);
    var ageMax = readInt(m['ageMax'], min: 10, max: 80);
    if (ageMin != null && ageMax != null && ageMin > ageMax) {
      // Swapped or broken limits: drop both rather than guess.
      ageMin = null;
      ageMax = null;
    }

    final posted = readInstant(m['postedAt']);
    return PostSummary(
      id: id as String,
      type: PostType.parse(m['type']),
      title: title,
      org: LocalText.tryParse(m['org']) ?? LocalText.empty,
      source: readString(m['source'], maxLength: 40),
      category: JobCategory.parse(m['category']),
      postedAt: posted,
      updatedAt: readInstant(m['updatedAt']) ?? posted,
      lastDate: readYmd(m['lastDate']),
      totalPosts: readInt(m['totalPosts'], min: 0, max: 10000000),
      qualifications: List.unmodifiable(quals),
      states: List.unmodifiable(states),
      ageMin: ageMin,
      ageMax: ageMax,
      salary: LocalText.tryParse(m['salary']),
      tags: List.unmodifiable(readStrings(m['tags'], lower: true)),
      verified: readBool(m['verified']),
    );
  }

  /// Round-trips through [tryParse]; used for saved jobs and alerts.
  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.wire,
        'title': title.toJson(),
        'org': org.toJson(),
        if (source != null) 'source': source,
        'category': category.wire,
        if (postedAt != null) 'postedAt': postedAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (lastDate != null) 'lastDate': lastDate.toString(),
        if (totalPosts != null) 'totalPosts': totalPosts,
        'qualifications': [for (final q in qualifications) q.wire],
        'states': states,
        if (ageMin != null) 'ageMin': ageMin,
        if (ageMax != null) 'ageMax': ageMax,
        if (salary != null) 'salary': salary!.toJson(),
        'tags': tags,
        'verified': verified,
      };

  /// True when open to candidates from [stateCode] (or the feed did not say).
  bool openToState(String? stateCode) =>
      stateCode == null ||
      states.isEmpty ||
      states.contains(allStates) ||
      states.contains(stateCode);

  /// Posts that follow standard central government age relaxations.
  bool get followsCentralRules =>
      tags.contains('central-govt') ||
      category == JobCategory.ssc ||
      category == JobCategory.upsc ||
      category == JobCategory.railway;

  /// The newest of posted/updated time, for "newest first" sorting.
  DateTime? get sortTime => updatedAt ?? postedAt;
}

class DateEntry {
  const DateEntry(this.label, this.date, this.text);
  final LocalText label;
  final Ymd? date;
  final LocalText? text;

  static DateEntry? tryParse(Object? json) {
    final m = readMap(json);
    if (m == null) return null;
    final label = LocalText.tryParse(m['label']);
    if (label == null) return null;
    final date = readYmd(m['date']);
    final text = LocalText.tryParse(m['text']);
    if (date == null && text == null) return null;
    return DateEntry(label, date, text);
  }
}

class FeeEntry {
  const FeeEntry(this.category, this.amount, this.text);
  final LocalText category;
  final int? amount;
  final LocalText? text;

  static FeeEntry? tryParse(Object? json) {
    final m = readMap(json);
    if (m == null) return null;
    final category = LocalText.tryParse(m['category']);
    if (category == null) return null;
    final amount = readInt(m['amount'], min: 0, max: 1000000);
    final text = LocalText.tryParse(m['text']);
    if (amount == null && text == null) return null;
    return FeeEntry(category, amount, text);
  }
}

class AgeInfo {
  const AgeInfo({this.min, this.max, this.asOn, this.relaxation});
  final int? min;
  final int? max;
  final Ymd? asOn;
  final LocalText? relaxation;

  static const unknown = AgeInfo();

  bool get isEmpty =>
      min == null && max == null && asOn == null && relaxation == null;

  static AgeInfo parse(Object? json) {
    final m = readMap(json);
    if (m == null) return unknown;
    var min = readInt(m['min'], min: 10, max: 80);
    var max = readInt(m['max'], min: 10, max: 80);
    if (min != null && max != null && min > max) {
      min = null;
      max = null;
    }
    return AgeInfo(
      min: min,
      max: max,
      asOn: readYmd(m['asOn']),
      relaxation: LocalText.tryParse(m['relaxation']),
    );
  }
}

class VacancyEntry {
  const VacancyEntry(this.post, this.total, this.breakdown);
  final LocalText post;
  final int? total;
  final LocalText? breakdown;

  static VacancyEntry? tryParse(Object? json) {
    final m = readMap(json);
    if (m == null) return null;
    final post = LocalText.tryParse(m['post']);
    if (post == null) return null;
    return VacancyEntry(
      post,
      readInt(m['total'], min: 0, max: 10000000),
      LocalText.tryParse(m['breakdown']),
    );
  }

  /// "UR 50, OBC 32, EWS 12" split into labelled counts. Parts that don't
  /// look like `label number` are skipped.
  List<(String, int)> get breakdownParts {
    final b = breakdown?.en;
    if (b == null) return const [];
    final out = <(String, int)>[];
    final part = RegExp(r'^\s*([A-Za-z][A-Za-z\-/ ().]*?)\s*[:\-]?\s*(\d[\d,]*)\s*$');
    for (final piece in b.split(RegExp(r'[,;|]'))) {
      final m = part.firstMatch(piece);
      if (m == null) continue;
      final n = int.tryParse(m.group(2)!.replaceAll(',', ''));
      if (n != null) out.add((m.group(1)!.trim(), n));
    }
    return out;
  }
}

class PostLink {
  const PostLink(this.label, this.url);
  final LocalText label;
  final String url;

  static PostLink? tryParse(Object? json) {
    final m = readMap(json);
    if (m == null) return null;
    final label = LocalText.tryParse(m['label']);
    final url = readUrl(m['url']);
    if (label == null || url == null) return null;
    return PostLink(label, url);
  }
}

class CheckInfo {
  const CheckInfo({this.model, this.rounds, this.factsChecked, this.factsDropped});
  final String? model;
  final int? rounds;
  final int? factsChecked;
  final int? factsDropped;

  static CheckInfo? tryParse(Object? json) {
    final m = readMap(json);
    if (m == null) return null;
    return CheckInfo(
      model: readString(m['model'], maxLength: 60),
      rounds: readInt(m['rounds'], min: 0, max: 100),
      factsChecked: readInt(m['factsChecked'], min: 0, max: 100000),
      factsDropped: readInt(m['factsDropped'], min: 0, max: 100000),
    );
  }
}

List<T> _parseAll<T>(Object? list, T? Function(Object?) parse, {int max = 200}) {
  final out = <T>[];
  for (final e in readList(list)) {
    if (out.length >= max) break;
    final v = parse(e);
    if (v != null) out.add(v);
  }
  return List.unmodifiable(out);
}

/// `jobs/posts/<id>.json`: every summary field plus the details.
class PostDetail {
  const PostDetail({
    required this.summary,
    this.shortInfo,
    this.importantDates = const [],
    this.fees = const [],
    this.age = AgeInfo.unknown,
    this.vacancies = const [],
    this.eligibility,
    this.selection = const [],
    this.howToApply,
    this.links = const [],
    this.officialNoticeUrl,
    this.sourcePageUrl,
    this.check,
  });

  final PostSummary summary;
  final LocalText? shortInfo;
  final List<DateEntry> importantDates;
  final List<FeeEntry> fees;
  final AgeInfo age;
  final List<VacancyEntry> vacancies;
  final LocalText? eligibility;
  final List<LocalText> selection;
  final LocalText? howToApply;
  final List<PostLink> links;
  final String? officialNoticeUrl;
  final String? sourcePageUrl;
  final CheckInfo? check;

  String get id => summary.id;

  static PostDetail? tryParse(Object? json) {
    final m = readMap(json);
    if (m == null) return null;
    final summary = PostSummary.tryParse(m);
    if (summary == null) return null;
    final age = AgeInfo.parse(m['age']);
    return PostDetail(
      summary: summary,
      shortInfo: LocalText.tryParse(m['shortInfo']),
      importantDates: _parseAll(m['importantDates'], DateEntry.tryParse),
      fees: _parseAll(m['fees'], FeeEntry.tryParse),
      age: age,
      vacancies: _parseAll(m['vacancies'], VacancyEntry.tryParse, max: 500),
      eligibility: LocalText.tryParse(m['eligibility']),
      selection: _parseAll(m['selection'], LocalText.tryParse, max: 30),
      howToApply: LocalText.tryParse(m['howToApply']),
      links: _parseAll(m['links'], PostLink.tryParse, max: 40),
      officialNoticeUrl: readUrl(m['officialNoticeUrl']),
      sourcePageUrl: readUrl(m['sourcePageUrl']),
      check: CheckInfo.tryParse(m['check']),
    );
  }

  /// Age limits from the detail, falling back to the summary's.
  int? get ageMin => age.min ?? summary.ageMin;
  int? get ageMax => age.max ?? summary.ageMax;

  /// Sum of the vacancy rows when the feed has no overall total.
  int? get totalPosts {
    if (summary.totalPosts != null) return summary.totalPosts;
    if (vacancies.isEmpty || vacancies.any((v) => v.total == null)) return null;
    return vacancies.fold<int>(0, (a, v) => a + v.total!);
  }
}
