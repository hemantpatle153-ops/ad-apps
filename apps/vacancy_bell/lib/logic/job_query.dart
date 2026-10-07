/// Search, filters and sorting for the post lists.
library;

import '../core/ymd.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/taxonomy.dart';
import 'eligibility.dart';

enum SortOrder { newest, closingSoon }

class JobQuery {
  const JobQuery({
    this.text = '',
    this.qualifications = const {},
    this.state,
    this.categories = const {},
    this.onlyEligible = false,
    this.hideClosed = false,
    this.sort = SortOrder.newest,
  });

  final String text;
  final Set<Qualification> qualifications;

  /// State code; posts open to all states always match.
  final String? state;
  final Set<JobCategory> categories;

  /// Hide posts the user clearly can't apply for (needs "My details").
  /// Posts the engine can't decide stay visible.
  final bool onlyEligible;
  final bool hideClosed;
  final SortOrder sort;

  static const none = JobQuery();

  /// Number of active filters (not counting text and sort), for the badge.
  int get activeFilters =>
      (qualifications.isNotEmpty ? 1 : 0) +
      (state != null ? 1 : 0) +
      (categories.isNotEmpty ? 1 : 0) +
      (onlyEligible ? 1 : 0) +
      (hideClosed ? 1 : 0);

  bool get isDefault =>
      text.trim().isEmpty && activeFilters == 0 && sort == SortOrder.newest;

  JobQuery copyWith({
    String? text,
    Set<Qualification>? qualifications,
    String? Function()? state,
    Set<JobCategory>? categories,
    bool? onlyEligible,
    bool? hideClosed,
    SortOrder? sort,
  }) =>
      JobQuery(
        text: text ?? this.text,
        qualifications: qualifications ?? this.qualifications,
        state: state != null ? state() : this.state,
        categories: categories ?? this.categories,
        onlyEligible: onlyEligible ?? this.onlyEligible,
        hideClosed: hideClosed ?? this.hideClosed,
        sort: sort ?? this.sort,
      );

  /// Same filters with nothing selected (keeps the search text).
  JobQuery cleared() => JobQuery(text: text);
}

final _nonWord = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

/// Lower-case words used for matching: punctuation becomes a space, so
/// "SSC-CGL" matches "ssc cgl".
String normalizeForSearch(String s) =>
    s.toLowerCase().replaceAll(_nonWord, ' ').trim();

List<String> searchTokens(String query) {
  final n = normalizeForSearch(query);
  if (n.isEmpty) return const [];
  return n.split(' ').where((t) => t.isNotEmpty).toList();
}

String _haystack(PostSummary p) => normalizeForSearch([
      p.title.en,
      p.title.hi,
      p.org.en,
      p.org.hi,
      p.category.wire.replaceAll('_', ' '),
      ...p.tags,
      p.id,
    ].join(' '));

/// True when every word of [query] appears in the post's title or
/// organisation (in either language), category, tags or id.
bool matchesSearch(PostSummary p, String query) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return true;
  final hay = _haystack(p);
  return tokens.every(hay.contains);
}

bool matchesQualification(PostSummary p, Set<Qualification> wanted) {
  if (wanted.isEmpty) return true;
  if (p.qualifications.contains(Qualification.any)) return true;
  return p.qualifications.any(wanted.contains);
}

bool matchesFilters(
  PostSummary p,
  JobQuery q, {
  required Ymd today,
  UserProfile profile = UserProfile.empty,
  EligibilityResult Function(PostSummary)? eligibility,
}) {
  if (q.categories.isNotEmpty && !q.categories.contains(p.category)) {
    return false;
  }
  if (!matchesQualification(p, q.qualifications)) return false;
  if (q.state != null && !p.openToState(q.state)) return false;
  if (q.hideClosed && Deadline.of(p.lastDate, today).isClosed) return false;
  if (q.onlyEligible && profile.canCheckEligibility) {
    final e = (eligibility ?? (s) => eligibilityForSummary(profile, s))(p);
    if (e.isNotEligible) return false;
  }
  return matchesSearch(p, q.text);
}

int _compareNewest(PostSummary a, PostSummary b) {
  final ta = a.postedAt ?? a.sortTime;
  final tb = b.postedAt ?? b.sortTime;
  if (ta == null && tb == null) return a.id.compareTo(b.id);
  if (ta == null) return 1;
  if (tb == null) return -1;
  final c = tb.compareTo(ta);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Open posts by last date (soonest first), then posts without a last date,
/// then closed posts (most recently closed first).
int Function(PostSummary, PostSummary) closingSoonComparator(Ymd today) {
  int rank(PostSummary p) {
    final d = Deadline.of(p.lastDate, today);
    if (d.urgency == Urgency.unknown) return 1;
    return d.isClosed ? 2 : 0;
  }

  return (a, b) {
    final ra = rank(a), rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    if (ra == 0) {
      final c = a.lastDate!.compareTo(b.lastDate!);
      if (c != 0) return c;
    } else if (ra == 2) {
      final c = b.lastDate!.compareTo(a.lastDate!);
      if (c != 0) return c;
    }
    return _compareNewest(a, b);
  };
}

/// Applies [q] to [posts] and returns a new sorted list.
List<PostSummary> applyQuery(
  Iterable<PostSummary> posts,
  JobQuery q, {
  required Ymd today,
  UserProfile profile = UserProfile.empty,
  EligibilityResult Function(PostSummary)? eligibility,
}) {
  final out = posts
      .where((p) => matchesFilters(p, q,
          today: today, profile: profile, eligibility: eligibility))
      .toList();
  out.sort(q.sort == SortOrder.newest
      ? _compareNewest
      : closingSoonComparator(today));
  return out;
}
