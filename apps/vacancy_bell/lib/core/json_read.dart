/// Defensive readers for feed JSON. Each returns null (or an empty list)
/// instead of throwing when a value is missing or has the wrong type, so one
/// bad field never takes down a whole post.
library;

import 'ymd.dart';

enum AppLang {
  en,
  hi;

  static AppLang? tryParse(Object? v) => switch (v) {
        'en' => AppLang.en,
        'hi' => AppLang.hi,
        _ => null,
      };
}

/// A text in English and Hindi (`{"en": "...", "hi": "..."}` in the feed).
class LocalText {
  const LocalText(this.en, this.hi);
  const LocalText.same(String text)
      : en = text,
        hi = text;

  final String en;
  final String hi;

  static const empty = LocalText('', '');

  bool get isEmpty => en.isEmpty && hi.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// The text in [lang], falling back to the other language when missing.
  String of(AppLang lang) => switch (lang) {
        AppLang.hi => hi.isNotEmpty ? hi : en,
        AppLang.en => en.isNotEmpty ? en : hi,
      };

  /// Accepts a `{en, hi}` map or a plain string (used for both languages).
  /// Returns null when there is no usable text.
  static LocalText? tryParse(Object? v) {
    if (v is String) {
      final s = cleanText(v);
      return s.isEmpty ? null : LocalText(s, s);
    }
    if (v is Map) {
      final en = v['en'] is String ? cleanText(v['en'] as String) : '';
      final hi = v['hi'] is String ? cleanText(v['hi'] as String) : '';
      if (en.isEmpty && hi.isEmpty) return null;
      return LocalText(en, hi);
    }
    return null;
  }

  Map<String, Object?> toJson() => {'en': en, 'hi': hi};

  @override
  bool operator ==(Object other) =>
      other is LocalText && other.en == en && other.hi == hi;

  @override
  int get hashCode => Object.hash(en, hi);

  @override
  String toString() => en.isNotEmpty ? en : hi;
}

final _controlChars = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');

/// Trims and removes control characters (keeps newlines and tabs).
String cleanText(String s) => s.replaceAll(_controlChars, '').trim();

String? readString(Object? v, {int maxLength = 2000}) {
  if (v is! String) return null;
  final s = cleanText(v);
  if (s.isEmpty) return null;
  return s.length > maxLength ? s.substring(0, maxLength) : s;
}

/// Integers, also from whole doubles (12.0) and digit strings ("1,200").
int? readInt(Object? v, {int? min, int? max}) {
  int? n;
  if (v is int) {
    n = v;
  } else if (v is double && v.isFinite && v == v.roundToDouble()) {
    n = v.toInt();
  } else if (v is String) {
    final digits = v.replaceAll(',', '').trim();
    n = int.tryParse(digits);
  }
  if (n == null) return null;
  if (min != null && n < min) return null;
  if (max != null && n > max) return null;
  return n;
}

bool readBool(Object? v, {bool fallback = false}) => v is bool ? v : fallback;

List<Object?> readList(Object? v) => v is List ? v : const [];

Map<String, Object?>? readMap(Object? v) {
  if (v is! Map) return null;
  final out = <String, Object?>{};
  v.forEach((k, val) {
    if (k is String) out[k] = val;
  });
  return out;
}

/// An ISO 8601 instant, always returned in UTC.
DateTime? readInstant(Object? v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v.trim());
  if (d == null) return null;
  if (d.year < 2000 || d.year > 2200) return null;
  return d.toUtc();
}

Ymd? readYmd(Object? v) => Ymd.tryParse(v);

/// Strings from a list, deduplicated, keeping order; non-strings skipped.
List<String> readStrings(Object? v, {bool lower = false}) {
  final out = <String>[];
  for (final e in readList(v)) {
    final s = readString(e, maxLength: 80);
    if (s == null) continue;
    final t = lower ? s.toLowerCase() : s;
    if (!out.contains(t)) out.add(t);
  }
  return out;
}

/// Only http(s) links with a host are kept; anything else (javascript:,
/// relative paths, typos) is dropped.
String? readUrl(Object? v) {
  final s = readString(v, maxLength: 2000);
  if (s == null) return null;
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  if (uri.host.isEmpty || !uri.host.contains('.')) return null;
  return s;
}

final _idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,119}$');

/// Post ids are `[a-z0-9-]`; anything else is rejected (they become file
/// names and URL paths).
bool isValidPostId(Object? v) => v is String && _idPattern.hasMatch(v);
