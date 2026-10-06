import 'dart:convert';
import 'dart:io';

/// One subtitle line's time span, in milliseconds of subtitle time.
class Cue {
  const Cue(this.startMs, this.endMs);
  final int startMs;
  final int endMs;

  @override
  String toString() => 'Cue($startMs-$endMs)';
}

/// "00:01:02,345", "01:02.345" (WebVTT) or "0:01:02.34" (ASS) to ms.
int? parseTimestamp(String s) {
  final m = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})$')
      .firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1) ?? '0');
  final min = int.parse(m.group(2)!);
  final sec = int.parse(m.group(3)!);
  final frac = m.group(4)!;
  final ms = int.parse(frac.padRight(3, '0'));
  return ((h * 60 + min) * 60 + sec) * 1000 + ms;
}

final _arrow = RegExp(r'^\s*(\S+)\s*-->\s*(\S+)');

/// Cue times from SRT, WebVTT or ASS/SSA text, sorted by start.
/// Lines it does not understand are skipped.
List<Cue> parseCues(String text) {
  final cues = <Cue>[];
  final lines = const LineSplitter().convert(text.replaceFirst('﻿', ''));
  for (final line in lines) {
    final arrow = _arrow.firstMatch(line);
    if (arrow != null) {
      final a = parseTimestamp(arrow.group(1)!);
      final b = parseTimestamp(arrow.group(2)!);
      if (a != null && b != null && b > a) cues.add(Cue(a, b));
      continue;
    }
    // ASS: "Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,Text"
    if (line.startsWith('Dialogue:')) {
      final parts = line.substring(9).split(',');
      if (parts.length < 3) continue;
      final a = parseTimestamp(parts[1]);
      final b = parseTimestamp(parts[2]);
      if (a != null && b != null && b > a) cues.add(Cue(a, b));
    }
  }
  cues.sort((x, y) => x.startMs.compareTo(y.startMs));
  return cues;
}

/// Reads a subtitle file as UTF-8, falling back to Latin-1 for old files.
Future<List<Cue>> readCues(String path) async {
  final bytes = await File(path).readAsBytes();
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = latin1.decode(bytes);
  }
  return parseCues(text);
}
