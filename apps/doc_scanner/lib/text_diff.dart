enum DiffOp { same, added, removed }

class DiffPart {
  const DiffPart(this.op, this.text);
  final DiffOp op;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffPart && other.op == op && other.text == text;
  @override
  int get hashCode => Object.hash(op, text);
  @override
  String toString() => '${op.name}:"$text"';
}

class DiffSummary {
  const DiffSummary(this.parts, this.added, this.removed, this.same);
  final List<DiffPart> parts;
  final int added;
  final int removed;
  final int same;

  bool get identical => added == 0 && removed == 0;

  /// Share of words that match, 0..1.
  double get similarity {
    final total = same + (added > removed ? added : removed);
    return total == 0 ? 1 : same / total;
  }
}

List<String> tokenize(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Word-level diff of two texts (longest common subsequence). Adjacent
/// words with the same op are merged into one part.
DiffSummary diffWords(String a, String b) {
  final x = tokenize(a);
  final y = tokenize(b);
  // Trim the shared start and end so long, mostly equal documents stay fast.
  var start = 0;
  while (start < x.length && start < y.length && x[start] == y[start]) {
    start++;
  }
  var endX = x.length;
  var endY = y.length;
  while (endX > start && endY > start && x[endX - 1] == y[endY - 1]) {
    endX--;
    endY--;
  }
  final mx = x.sublist(start, endX);
  final my = y.sublist(start, endY);
  final ops = <(DiffOp, String)>[
    for (final w in x.sublist(0, start)) (DiffOp.same, w),
  ];
  if (mx.length * my.length > 4000000) {
    // Too big for a full table: report the middle as replaced.
    ops.addAll([for (final w in mx) (DiffOp.removed, w)]);
    ops.addAll([for (final w in my) (DiffOp.added, w)]);
  } else {
    final n = mx.length, m = my.length;
    final t = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        t[i][j] = mx[i] == my[j]
            ? t[i + 1][j + 1] + 1
            : (t[i + 1][j] >= t[i][j + 1] ? t[i + 1][j] : t[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (mx[i] == my[j]) {
        ops.add((DiffOp.same, mx[i]));
        i++;
        j++;
      } else if (t[i + 1][j] >= t[i][j + 1]) {
        ops.add((DiffOp.removed, mx[i++]));
      } else {
        ops.add((DiffOp.added, my[j++]));
      }
    }
    while (i < n) {
      ops.add((DiffOp.removed, mx[i++]));
    }
    while (j < m) {
      ops.add((DiffOp.added, my[j++]));
    }
  }
  ops.addAll([for (final w in x.sublist(endX)) (DiffOp.same, w)]);

  final parts = <DiffPart>[];
  var added = 0, removed = 0, same = 0;
  for (final (op, w) in ops) {
    switch (op) {
      case DiffOp.added:
        added++;
      case DiffOp.removed:
        removed++;
      case DiffOp.same:
        same++;
    }
    if (parts.isNotEmpty && parts.last.op == op) {
      parts[parts.length - 1] = DiffPart(op, '${parts.last.text} $w');
    } else {
      parts.add(DiffPart(op, w));
    }
  }
  return DiffSummary(parts, added, removed, same);
}
