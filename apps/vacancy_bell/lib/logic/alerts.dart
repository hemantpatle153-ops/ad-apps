/// New post alerts: which posts in a fresh index are worth a notification.
library;

import '../core/json_read.dart';
import '../core/ymd.dart';
import '../models/feed_index.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/taxonomy.dart';
import 'eligibility.dart';

class AlertPrefs {
  const AlertPrefs({
    this.enabled = true,
    this.categories = const {},
    this.types = const {PostType.job},
    this.matchProfile = true,
  });

  final bool enabled;

  /// Categories to alert on; empty = every category.
  final Set<JobCategory> categories;

  /// Post types to alert on (new jobs by default; admit cards and results
  /// can be added).
  final Set<PostType> types;

  /// Use "My details" (state, qualification, age) to skip posts the user
  /// clearly can't apply for.
  final bool matchProfile;

  static const defaults = AlertPrefs();

  AlertPrefs copyWith({
    bool? enabled,
    Set<JobCategory>? categories,
    Set<PostType>? types,
    bool? matchProfile,
  }) =>
      AlertPrefs(
        enabled: enabled ?? this.enabled,
        categories: categories ?? this.categories,
        types: types ?? this.types,
        matchProfile: matchProfile ?? this.matchProfile,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'categories': [for (final c in categories) c.wire],
        'types': [for (final t in types) t.wire],
        'matchProfile': matchProfile,
      };

  static AlertPrefs fromJson(Object? json) {
    final m = readMap(json);
    if (m == null) return defaults;
    final cats = <JobCategory>{
      for (final c in readList(m['categories']))
        if (JobCategory.tryParse(c) != null) JobCategory.tryParse(c)!,
    };
    final rawTypes = m['types'];
    final types = <PostType>{
      for (final t in readList(rawTypes))
        if (PostType.tryParse(t) != null) PostType.tryParse(t)!,
    };
    return AlertPrefs(
      enabled: readBool(m['enabled'], fallback: true),
      categories: cats,
      types: rawTypes is List ? types : defaults.types,
      matchProfile: readBool(m['matchProfile'], fallback: true),
    );
  }
}

/// Posts older than this are never announced, even if unseen (for example
/// after the app's data was cleared).
const alertMaxAge = Duration(days: 3);

/// Whether [p] is something the user asked to be alerted about.
bool alertMatches(
  PostSummary p,
  AlertPrefs prefs,
  UserProfile profile, {
  required DateTime now,
}) {
  if (!prefs.types.contains(p.type)) return false;
  if (prefs.categories.isNotEmpty && !prefs.categories.contains(p.category)) {
    return false;
  }
  final posted = p.postedAt;
  if (posted == null || now.difference(posted) > alertMaxAge) return false;
  final today = Ymd.istOf(now);
  if (Deadline.of(p.lastDate, today).isClosed) return false;
  if (prefs.matchProfile) {
    if (!p.openToState(profile.state)) return false;
    // Only jobs are checked against qualification and age: an admit card
    // or result matters to people who already applied.
    if (p.type == PostType.job &&
        eligibilityForSummary(profile, p).isNotEligible) {
      return false;
    }
  }
  return true;
}

class AlertCheck {
  const AlertCheck({required this.matches, required this.seen, required this.seeded});

  /// New posts to notify about, newest first.
  final List<PostSummary> matches;

  /// The ids to remember as seen after this check, newest first.
  final List<String> seen;

  /// First check ever: everything was marked seen and nothing announced.
  final bool seeded;
}

/// Compares [index] with the ids already [seen]. On the very first check
/// ([seen] is null) nothing is announced, so installing the app doesn't
/// produce a burst of notifications.
AlertCheck findNewAlerts(
  FeedIndex index,
  List<String>? seen,
  AlertPrefs prefs,
  UserProfile profile, {
  required DateTime now,
}) {
  final ids = [for (final p in index.posts) p.id];
  if (seen == null) {
    return AlertCheck(
        matches: const [], seen: ids.take(maxSeenIds).toList(), seeded: true);
  }
  final known = seen.toSet();
  final matches = <PostSummary>[];
  if (prefs.enabled) {
    for (final p in index.posts) {
      if (known.contains(p.id)) continue;
      if (alertMatches(p, prefs, profile, now: now)) matches.add(p);
    }
  }
  // Remember the feed's ids plus the most recent older ones, so a post that
  // drops out and comes back is not announced twice.
  final kept = <String>{...ids, ...seen};
  return AlertCheck(
      matches: matches, seen: kept.take(maxSeenIds).toList(), seeded: false);
}

const maxSeenIds = 2000;

/// More than this many matches become one summary notification.
const maxSingleAlerts = 3;

class AlertMessage {
  const AlertMessage({
    required this.id,
    required this.title,
    required this.body,
    this.postId,
  });
  final int id;
  final String title;
  final String body;

  /// Opens this post when tapped (null for the summary).
  final String? postId;
}

/// FNV-1a 32-bit hash, stable across runs and isolates (unlike hashCode).
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Notification ids: reminders use [reminderIdBase]..+40M, alerts
/// [alertIdBase]..+10M, and [alertSummaryId] for the grouped alert. All fit
/// in a signed 32-bit int as Android requires.
const reminderIdBase = 10000;
const alertIdBase = 50000000;
const alertSummaryId = 1;
const _idSpan = 10000000;

int alertNotificationId(String postId) =>
    alertIdBase + stableHash(postId) % _idSpan;

int reminderNotificationId(String postId, int daysBefore) =>
    reminderIdBase + (stableHash(postId) % _idSpan) * 4 + (daysBefore % 4);

bool isReminderNotificationId(int id) =>
    id >= reminderIdBase && id < reminderIdBase + _idSpan * 4;

/// Turns matches into notifications using [text] for the wording.
List<AlertMessage> buildAlertMessages(
  List<PostSummary> matches,
  AppLang lang, {
  required String Function(PostSummary p) singleTitle,
  required String Function(PostSummary p) singleBody,
  required String Function(int count) summaryTitle,
  required String Function(List<PostSummary> top) summaryBody,
}) {
  if (matches.isEmpty) return const [];
  if (matches.length > maxSingleAlerts) {
    return [
      AlertMessage(
        id: alertSummaryId,
        title: summaryTitle(matches.length),
        body: summaryBody(matches.take(3).toList()),
      ),
    ];
  }
  return [
    for (final p in matches)
      AlertMessage(
        id: alertNotificationId(p.id),
        title: singleTitle(p),
        body: singleBody(p),
        postId: p.id,
      ),
  ];
}
