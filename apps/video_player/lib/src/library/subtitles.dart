import 'dart:io';

/// Extensions the player can load as external subtitles.
const subtitleExtensions = ['srt', 'ass', 'ssa', 'vtt', 'sub'];

/// Files next to [videoPath] that could be its subtitles, best match first:
/// "Movie.srt", then "Movie.en.srt" style names.
List<String> sidecarCandidates(String videoPath) {
  final dot = videoPath.lastIndexOf('.');
  final slash = videoPath.lastIndexOf('/');
  final base = dot > slash ? videoPath.substring(0, dot) : videoPath;
  return [
    for (final ext in subtitleExtensions) '$base.$ext',
    for (final lang in ['en', 'eng', 'hi', 'hin'])
      for (final ext in ['srt', 'ass', 'vtt']) '$base.$lang.$ext',
  ];
}

/// Returns the first matching subtitle file that exists and can be read.
///
/// Android 11+ only lets apps read media files, so this finds .srt files
/// on older phones; on newer ones the user picks the file instead.
Future<String?> findSidecarSubtitle(String? videoPath) async {
  if (videoPath == null || videoPath.startsWith('http')) return null;
  for (final c in sidecarCandidates(videoPath)) {
    try {
      final f = File(c);
      if (await f.exists()) {
        await f.openRead(0, 1).drain<void>();
        return c;
      }
    } catch (_) {}
  }
  return null;
}
