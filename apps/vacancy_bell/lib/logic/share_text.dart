import '../config.dart';
import '../l10n/s.dart';
import '../l10n/strings.dart';
import '../models/post.dart';
import '../models/taxonomy.dart';

/// The text sent when the user shares a post: key facts, a reminder to
/// verify, and a link to the app. Only facts the feed has are included.
String buildShareText(S s, PostSummary p, {PostDetail? detail}) {
  final lines = <String>[s.text(p.title)];
  final org = s.text(p.org);
  if (org.isNotEmpty) lines.add(org);
  lines.add('');
  final total = detail?.totalPosts ?? p.totalPosts;
  if (total != null) lines.add(s.t(L.sharePosts, {'n': S.number(total)}));
  if (p.lastDate != null) {
    lines.add(s.t(L.shareLastDate, {'date': s.date(p.lastDate!)}));
  }
  final quals = p.qualifications.where((q) => q != Qualification.any).toList();
  if (quals.isNotEmpty) {
    lines.add(s.t(L.shareQualification,
        {'q': quals.map(s.qualification).join(' / ')}));
  }
  final range = s.ageRange(detail?.ageMin ?? p.ageMin, detail?.ageMax ?? p.ageMax);
  if (range != null) lines.add(s.t(L.shareAge, {'range': range}));
  final official = detail?.officialNoticeUrl ?? detail?.sourcePageUrl;
  if (official != null) lines.add(official);
  lines
    ..add('')
    ..add(s.t(L.shareVerify))
    ..add(s.t(L.shareVia, {'link': AppConfig.playLink}));
  // Collapse the blank line left when no facts were added.
  final out = <String>[];
  for (final l in lines) {
    if (l.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(l);
  }
  return out.join('\n');
}
