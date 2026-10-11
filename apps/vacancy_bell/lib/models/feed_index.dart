import 'dart:convert';

import '../core/json_read.dart';
import 'post.dart';

/// `jobs/index.json`.
class FeedIndex {
  const FeedIndex({
    required this.schema,
    required this.generatedAt,
    required this.posts,
    this.skipped = 0,
  });

  final int schema;
  final DateTime? generatedAt;

  /// Valid posts, newest first as published, without duplicate ids.
  final List<PostSummary> posts;

  /// How many entries were dropped as malformed or duplicates.
  final int skipped;

  static const maxPosts = 600;

  static final empty = FeedIndex(schema: 1, generatedAt: null, posts: const []);

  /// Parses a decoded index. Throws [FormatException] only when the file as
  /// a whole is unusable (not an object, or no `posts` list).
  factory FeedIndex.fromJson(Object? json) {
    final m = readMap(json);
    if (m == null) throw const FormatException('index is not an object');
    final rawPosts = m['posts'];
    if (rawPosts is! List) throw const FormatException('index has no posts');
    final seen = <String>{};
    final posts = <PostSummary>[];
    var skipped = 0;
    for (final raw in rawPosts) {
      if (posts.length >= maxPosts) {
        skipped++;
        continue;
      }
      final p = PostSummary.tryParse(raw);
      if (p == null || !seen.add(p.id)) {
        skipped++;
        continue;
      }
      posts.add(p);
    }
    return FeedIndex(
      schema: readInt(m['schema'], min: 0) ?? 1,
      generatedAt: readInstant(m['generatedAt']),
      posts: List.unmodifiable(posts),
      skipped: skipped,
    );
  }

  /// Decodes and parses a JSON string. Throws [FormatException].
  static FeedIndex parse(String body) => FeedIndex.fromJson(jsonDecode(body));

  PostSummary? byId(String id) {
    for (final p in posts) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Decodes and parses a post file. Throws [FormatException] when the file is
/// not a usable post.
PostDetail parsePostDetail(String body) {
  final d = PostDetail.tryParse(jsonDecode(body));
  if (d == null) throw const FormatException('not a valid post');
  return d;
}
