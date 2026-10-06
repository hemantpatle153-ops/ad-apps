import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// This phone's IPv4 addresses on local networks (Wi-Fi, hotspot), best
/// first. Mobile data addresses are left out: guests can't reach them.
Future<List<String>> localAddresses() async {
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  } on SocketException {
    return [];
  }
  int rank(NetworkInterface i) {
    final n = i.name.toLowerCase();
    if (n.startsWith('wlan') || n.startsWith('ap') || n.startsWith('swlan')) {
      return 0;
    }
    if (n.startsWith('eth') || n.startsWith('en') || n.startsWith('rndis')) {
      return 1;
    }
    if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('tun')) {
      return 9;
    }
    return 2;
  }

  final list = interfaces.where((i) => rank(i) < 9).toList()
    ..sort((a, b) => rank(a).compareTo(rank(b)));
  return [
    for (final i in list)
      for (final a in i.addresses)
        if (!a.isLoopback && !a.isLinkLocal && _isPrivate(a.address)) a.address,
  ];
}

bool _isPrivate(String ip) {
  final p = ip.split('.').map(int.parse).toList();
  return p[0] == 10 ||
      (p[0] == 172 && p[1] >= 16 && p[1] < 32) ||
      (p[0] == 192 && p[1] == 168);
}

/// The host announces itself on the local network once a second so guests
/// can tap it in a list instead of scanning the QR code.
class Beacon {
  Beacon._(this._socket, this._payload, this._targets);

  final RawDatagramSocket _socket;
  final List<int> _payload;
  final List<InternetAddress> _targets;
  Timer? _timer;

  static Future<Beacon?> start(
      {required String name, required int port, required List<String> addresses}) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
        ..broadcastEnabled = true;
      final payload = utf8.encode(jsonEncode(
          {'app': 'vparty', 'v': partyProtocol, 'name': name, 'port': port}));
      // A hotspot often drops 255.255.255.255, so also aim at each /24.
      final targets = {
        '255.255.255.255',
        for (final a in addresses) '${a.substring(0, a.lastIndexOf('.'))}.255',
      }.map(InternetAddress.new).toList();
      final b = Beacon._(socket, payload, targets);
      b._send();
      b._timer = Timer.periodic(const Duration(seconds: 1), (_) => b._send());
      return b;
    } on SocketException {
      return null;
    }
  }

  void _send() {
    for (final t in _targets) {
      try {
        _socket.send(_payload, t, partyBeaconPort);
      } on SocketException {
        // Not on that network any more; the next beat tries again.
      }
    }
  }

  void stop() {
    _timer?.cancel();
    _socket.close();
  }
}

class FoundHost {
  FoundHost({required this.address, required this.port, required this.name});

  final String address;
  final int port;
  final String name;
  DateTime lastSeen = DateTime.now();

  JoinCode get joinCode => JoinCode(hosts: [address], port: port, name: name);
}

/// Listens for host beacons and keeps a list of parties nearby.
class BeaconListener {
  BeaconListener._(this._socket);

  final RawDatagramSocket _socket;
  final Map<String, FoundHost> _hosts = {};
  final _controller = StreamController<List<FoundHost>>.broadcast();
  Timer? _expire;

  Stream<List<FoundHost>> get hosts => _controller.stream;

  static Future<BeaconListener?> start() async {
    try {
      final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, partyBeaconPort,
          reuseAddress: true);
      final l = BeaconListener._(socket);
      socket.listen(l._onEvent);
      l._expire = Timer.periodic(const Duration(seconds: 2), (_) => l._prune());
      return l;
    } on SocketException {
      return null;
    }
  }

  void _onEvent(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final d = _socket.receive();
    if (d == null) return;
    try {
      final j = jsonDecode(utf8.decode(d.data));
      if (j is! Map || j['app'] != 'vparty' || j['port'] is! int) return;
      final ip = d.address.address;
      final h = _hosts[ip];
      if (h != null && h.port == j['port']) {
        h.lastSeen = DateTime.now();
        return;
      }
      _hosts[ip] = FoundHost(
          address: ip, port: j['port'] as int, name: '${j['name'] ?? ip}');
      _emit();
    } on FormatException {
      // Someone else's packet on our port.
    }
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 5));
    final before = _hosts.length;
    _hosts.removeWhere((_, h) => h.lastSeen.isBefore(cutoff));
    if (_hosts.length != before) _emit();
  }

  void _emit() => _controller.add(_hosts.values.toList());

  void stop() {
    _expire?.cancel();
    _socket.close();
    _controller.close();
  }
}
