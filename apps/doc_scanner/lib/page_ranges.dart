/// Parses page ranges such as "1-3, 5, 8-" into zero-based indexes.
/// Throws [FormatException] with a readable message on bad input.
List<int> parsePageRange(String input, int pageCount) {
  final out = <int>[];
  final parts = input.split(RegExp(r'[,;\s]+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) throw const FormatException('Enter page numbers.');
  for (final part in parts) {
    final m = RegExp(r'^(\d*)\s*-\s*(\d*)$').firstMatch(part);
    int from;
    int to;
    if (m != null) {
      from = m.group(1)!.isEmpty ? 1 : int.parse(m.group(1)!);
      to = m.group(2)!.isEmpty ? pageCount : int.parse(m.group(2)!);
    } else {
      final n = int.tryParse(part);
      if (n == null) throw FormatException('"$part" is not a page number.');
      from = to = n;
    }
    if (from < 1 || to > pageCount || from > to) {
      throw FormatException(
          '"$part" is outside pages 1 to $pageCount.');
    }
    for (var p = from; p <= to; p++) {
      out.add(p - 1);
    }
  }
  return out;
}

/// Splits each comma-separated range into its own group, e.g. "1-2, 3-5"
/// gives two files.
List<List<int>> parseSplitGroups(String input, int pageCount) => [
      for (final part in input.split(',').where((p) => p.trim().isNotEmpty))
        parsePageRange(part, pageCount),
    ];

/// Groups of [size] pages: 1-size, size+1-2*size, ...
List<List<int>> fixedGroups(int pageCount, int size) {
  if (size < 1) throw const FormatException('Pages per file must be 1 or more.');
  return [
    for (var s = 0; s < pageCount; s += size)
      [for (var i = s; i < s + size && i < pageCount; i++) i],
  ];
}
