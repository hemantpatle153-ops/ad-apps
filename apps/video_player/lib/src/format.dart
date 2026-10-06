/// Small text helpers shared by the lists and the player.
library;

/// 75 s -> "1:15", 3725 s -> "1:02:05".
String formatDuration(Duration d) {
  final neg = d.isNegative;
  final total = d.abs().inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  final text = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  return neg ? '-$text' : text;
}

/// Bytes -> "740 KB", "12.4 MB", "1.27 GB".
String formatSize(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = i <= 1 || v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits)} ${units[i]}';
}

/// Short quality label from the video height: "4K", "1080p", "720p".
String qualityLabel(int width, int height) {
  final p = width < height ? width : height;
  if (p <= 0) return '';
  if (p >= 2000) return '4K';
  if (p >= 1400) return '1440p';
  if (p >= 1000) return '1080p';
  if (p >= 700) return '720p';
  if (p >= 460) return '480p';
  return '${p}p';
}

/// Speed as the player shows it: 1.0 -> "1x", 0.25 -> "0.25x".
String formatSpeed(double speed) {
  var t = speed.toStringAsFixed(2);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '${t}x';
}
