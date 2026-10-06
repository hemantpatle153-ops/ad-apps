import 'dart:convert';

/// TCP port the host listens on (HTTP for the video, WebSocket for control).
/// If it is busy the host picks another and puts it in the QR code.
const partyPort = 47810;

/// UDP port for the host's "I'm here" beacon on the local network.
const partyBeaconPort = 47811;

const partyProtocol = 1;

/// What every phone should be showing, on the host's clock.
///
/// While playing, the video position at host time `T` is
/// `positionUs + (T - anchorUs) * rate`.
class PartyState {
  const PartyState({
    required this.playing,
    required this.positionUs,
    required this.anchorUs,
    this.rate = 1,
  });

  static const start = PartyState(playing: false, positionUs: 0, anchorUs: 0);

  final bool playing;
  final int positionUs;
  final int anchorUs;
  final double rate;

  int positionAt(int hostNowUs) => playing
      ? positionUs + ((hostNowUs - anchorUs) * rate).round()
      : positionUs;

  Map<String, Object?> toJson() =>
      {'playing': playing, 'pos': positionUs, 'at': anchorUs, 'rate': rate};

  factory PartyState.fromJson(Map<String, Object?> j) => PartyState(
        playing: j['playing'] == true,
        positionUs: (j['pos'] as num?)?.toInt() ?? 0,
        anchorUs: (j['at'] as num?)?.toInt() ?? 0,
        rate: (j['rate'] as num?)?.toDouble() ?? 1,
      );
}

/// The video the party is watching. Phone files are streamed from the host
/// at `/video`; a link is opened by every phone directly.
class PartyVideo {
  const PartyVideo({required this.title, this.url});

  final String title;

  /// Set when the video is an internet link everyone can open themselves.
  final String? url;

  Map<String, Object?> toJson() => {'title': title, 'url': url};

  factory PartyVideo.fromJson(Map<String, Object?> j) =>
      PartyVideo(title: '${j['title'] ?? 'Video'}', url: j['url'] as String?);
}

/// A chat line or an emoji reaction.
class PartyMessage {
  PartyMessage({required this.from, required this.text, this.emoji = false});

  final String from;
  final String text;
  final bool emoji;
  final DateTime at = DateTime.now();
}

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

/// What the QR code carries: every local address of the host, its port
/// and the party name.
class JoinCode {
  const JoinCode({required this.hosts, required this.port, required this.name});

  final List<String> hosts;
  final int port;
  final String name;

  static const scheme = 'vparty';

  String encode() => Uri(
        scheme: scheme,
        host: 'join',
        queryParameters: {
          'h': hosts.join(','),
          'p': '$port',
          'n': name,
          'v': '$partyProtocol',
        },
      ).toString();

  /// Reads a scanned QR code, or a typed `192.168.1.5` / `192.168.1.5:47810`.
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
          hosts: hosts, port: port, name: uri.queryParameters['n'] ?? 'Party');
    }
    final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$').firstMatch(text);
    if (m == null) return null;
    if (m.group(1)!.split('.').any((p) => int.parse(p) > 255)) return null;
    return JoinCode(
      hosts: [m.group(1)!],
      port: m.group(2) == null ? partyPort : int.parse(m.group(2)!),
      name: m.group(1)!,
    );
  }
}

/// Byte range from an HTTP Range header ("bytes=100-", "bytes=100-199",
/// "bytes=-500"), clamped to a file of [length] bytes. Null when there is
/// no usable range, which means "send the whole file".
(int, int)? parseRange(String? header, int length) {
  if (header == null || length <= 0) return null;
  final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (m == null) return null;
  final a = m.group(1)!, b = m.group(2)!;
  int start, end;
  if (a.isEmpty) {
    if (b.isEmpty) return null;
    final n = int.parse(b);
    start = length - n < 0 ? 0 : length - n;
    end = length - 1;
  } else {
    start = int.parse(a);
    end = b.isEmpty ? length - 1 : int.parse(b);
  }
  if (start >= length || end < start) return null;
  if (end >= length) end = length - 1;
  return (start, end);
}
