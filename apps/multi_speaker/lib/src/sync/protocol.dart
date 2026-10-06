import 'dart:convert';

/// TCP port the host listens on for guests (HTTP for songs, WebSocket for
/// control). If it is busy the host picks another and puts it in the QR code.
const hostPort = 47800;

/// UDP port for the host's "I'm here" beacon on the local network.
const beaconPort = 47801;

const protocolVersion = 1;

/// A song in the party playlist. The host serves its bytes at
/// `/track/<id>`.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.ext,
    required this.size,
  });

  final String id;
  final String title;

  /// File extension without the dot (mp3, m4a...), kept so the guest's
  /// player recognises the format of the downloaded file.
  final String ext;
  final int size;

  Map<String, Object?> toJson() =>
      {'id': id, 'title': title, 'ext': ext, 'size': size};

  factory Track.fromJson(Map<String, Object?> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String,
        ext: j['ext'] as String,
        size: j['size'] as int,
      );
}

/// What every speaker should be doing, on the host's clock.
///
/// While playing, the song position at host time `T` is
/// `positionUs + (T - anchorUs)`. The anchor can be in the future: the host
/// schedules starts slightly ahead so every phone can be ready on time.
class PlayState {
  const PlayState({
    required this.trackId,
    required this.playing,
    required this.positionUs,
    required this.anchorUs,
  });

  static const idle =
      PlayState(trackId: null, playing: false, positionUs: 0, anchorUs: 0);

  final String? trackId;
  final bool playing;
  final int positionUs;
  final int anchorUs;

  /// Song position at host time [hostNowUs]. Negative before a scheduled
  /// start at the very beginning of a song.
  int positionAt(int hostNowUs) =>
      playing ? positionUs + (hostNowUs - anchorUs) : positionUs;

  Map<String, Object?> toJson() => {
        'track': trackId,
        'playing': playing,
        'pos': positionUs,
        'at': anchorUs,
      };

  factory PlayState.fromJson(Map<String, Object?> j) => PlayState(
        trackId: j['track'] as String?,
        playing: j['playing'] as bool,
        positionUs: j['pos'] as int,
        anchorUs: j['at'] as int,
      );
}

/// Encodes one WebSocket message: a JSON object with a type field `t`.
String encodeMessage(String type, [Map<String, Object?> body = const {}]) =>
    jsonEncode({'t': type, ...body});

Map<String, Object?>? decodeMessage(Object? data) {
  if (data is! String) return null;
  try {
    final v = jsonDecode(data);
    return v is Map<String, Object?> && v['t'] is String ? v : null;
  } on FormatException {
    return null;
  }
}

/// What the QR code carries: every address the host has on the local
/// network (Wi-Fi and hotspot can differ), its port and its name.
class JoinCode {
  const JoinCode({required this.hosts, required this.port, required this.name});

  final List<String> hosts;
  final int port;
  final String name;

  static const scheme = 'msync';

  String encode() => Uri(
        scheme: scheme,
        host: 'join',
        queryParameters: {
          'h': hosts.join(','),
          'p': '$port',
          'n': name,
          'v': '$protocolVersion',
        },
      ).toString();

  /// Reads a scanned QR code, or a typed address like `192.168.1.5` or
  /// `192.168.1.5:47800`. Returns null for anything else.
  static JoinCode? parse(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    if (uri != null && uri.scheme == scheme) {
      final hosts = (uri.queryParameters['h'] ?? '')
          .split(',')
          .where((h) => h.isNotEmpty)
          .toList();
      final port = int.tryParse(uri.queryParameters['p'] ?? '');
      if (hosts.isEmpty || port == null) return null;
      return JoinCode(
          hosts: hosts, port: port, name: uri.queryParameters['n'] ?? 'Host');
    }
    final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$')
        .firstMatch(text);
    if (m == null) return null;
    if (m.group(1)!.split('.').any((p) => int.parse(p) > 255)) return null;
    return JoinCode(
      hosts: [m.group(1)!],
      port: m.group(2) == null ? hostPort : int.parse(m.group(2)!),
      name: m.group(1)!,
    );
  }
}
