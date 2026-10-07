/// The two languages of the app and of every feed text.
enum Lang {
  en,
  hi;

  static Lang parse(Object? v) => v == 'hi' ? Lang.hi : Lang.en;

  Lang get other => this == Lang.en ? Lang.hi : Lang.en;
}

/// A bilingual text, `{"en": "...", "hi": "..."}` in the feed.
///
/// When one language is missing the other is shown, so a half-translated
/// item is still usable.
class Bi {
  const Bi(this.en, this.hi);

  /// The same text in both languages (numbers, names).
  const Bi.same(String text) : this(text, text);

  final String en;
  final String hi;

  String of(Lang lang) => lang == Lang.hi ? hi : en;

  /// Whether the Hindi text is a real translation rather than a copy.
  bool get hasHindi => hi.isNotEmpty && hi != en;

  /// Parses `{"en", "hi"}` or a bare string. Null when there is no usable
  /// text at all.
  static Bi? tryParse(Object? json) {
    if (json is String) {
      final t = json.trim();
      return t.isEmpty ? null : Bi(t, t);
    }
    if (json is Map) {
      final en = json['en'] is String ? (json['en'] as String).trim() : '';
      final hi = json['hi'] is String ? (json['hi'] as String).trim() : '';
      if (en.isEmpty && hi.isEmpty) return null;
      return Bi(en.isEmpty ? hi : en, hi.isEmpty ? en : hi);
    }
    return null;
  }

  Map<String, String> toJson() => {'en': en, 'hi': hi};

  @override
  bool operator ==(Object other) =>
      other is Bi && other.en == en && other.hi == hi;

  @override
  int get hashCode => Object.hash(en, hi);

  @override
  String toString() => en;
}
