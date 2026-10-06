import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'backend.dart';

enum PeerVoice { connecting, connected, failed }

/// Group voice call for an online room: every phone talks directly to every
/// other phone (at most three links). WebRTC encrypts all audio end to end
/// with DTLS-SRTP; the room server only passes the connection details.
class VoiceChat {
  VoiceChat(this.backend, this.code, this.mySeat);

  final RoomBackend backend;
  final String code;
  final int mySeat;

  /// Public STUN servers find each phone's internet address. Some mobile
  /// networks also need a TURN relay; add one here when that shows up.
  static const _ice = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ],
  };

  final peers = ValueNotifier<Map<int, PeerVoice>>({});
  final muted = ValueNotifier(false);
  final speaker = ValueNotifier(true);

  /// Set when the microphone couldn't be opened (permission refused).
  final error = ValueNotifier<String?>(null);

  MediaStream? _mic;
  final _pcs = <int, RTCPeerConnection>{};
  final _pendingIce = <int, List<RTCIceCandidate>>{};
  final _calling = <int>{};
  StreamSubscription<Signal>? _signals;
  StreamSubscription<RoomState?>? _room;
  bool _closed = false;

  Future<void> start() async {
    try {
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
    } catch (_) {
      error.value = 'Allow the microphone to talk with friends';
      return;
    }
    if (_closed) return _mic?.dispose();
    await Helper.setSpeakerphoneOn(speaker.value).catchError((_) {});
    _signals = backend.signals(code, mySeat).listen(_onSignal);
    // The lower seat calls the higher one, so each pair makes one call.
    _room = backend.watchRoom(code).listen((room) {
      if (room == null) return;
      for (final e in room.seats.entries) {
        final s = e.key;
        if (s == mySeat) continue;
        if (!e.value.online) {
          _hangUp(s);
        } else if (s > mySeat && !_pcs.containsKey(s) && _calling.add(s)) {
          _call(s)
              .catchError((_) => _set(s, PeerVoice.failed))
              .whenComplete(() => _calling.remove(s));
        }
      }
    });
  }

  void _set(int seat, PeerVoice? v) {
    final m = Map.of(peers.value);
    v == null ? m.remove(seat) : m[seat] = v;
    peers.value = m;
  }

  Future<RTCPeerConnection> _connection(int seat) async {
    final old = _pcs[seat];
    if (old != null) return old;
    final pc = await createPeerConnection(_ice);
    _pcs[seat] = pc;
    _set(seat, PeerVoice.connecting);
    for (final t in _mic!.getAudioTracks()) {
      await pc.addTrack(t, _mic!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      backend
          .sendSignal(
              code,
              seat,
              Signal(from: mySeat, type: 'ice', data: {
                'candidate': c.candidate,
                'sdpMid': c.sdpMid,
                'sdpMLineIndex': c.sdpMLineIndex,
              }))
          .ignore();
    };
    pc.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _set(seat, PeerVoice.connected);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _set(seat, PeerVoice.failed);
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _set(seat, null);
        default:
      }
    };
    // Remote audio tracks play by themselves on Android and iOS.
    return pc;
  }

  Future<void> _call(int seat) async {
    final pc = await _connection(seat);
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    await backend.sendSignal(code, seat,
        Signal(from: mySeat, type: 'offer', data: {'sdp': offer.sdp}));
  }

  Future<void> _onSignal(Signal s) async {
    if (_closed || _mic == null) return;
    try {
      switch (s.type) {
        case 'offer':
          // A fresh offer replaces any half-made call from that seat.
          await _hangUp(s.from);
          final pc = await _connection(s.from);
          await pc.setRemoteDescription(
              RTCSessionDescription(s.data['sdp'] as String, 'offer'));
          await _flushIce(s.from);
          final answer = await pc.createAnswer({'offerToReceiveAudio': true});
          await pc.setLocalDescription(answer);
          await backend.sendSignal(code, s.from,
              Signal(from: mySeat, type: 'answer', data: {'sdp': answer.sdp}));
        case 'answer':
          final pc = _pcs[s.from];
          if (pc == null) return;
          await pc.setRemoteDescription(
              RTCSessionDescription(s.data['sdp'] as String, 'answer'));
          await _flushIce(s.from);
        case 'ice':
          final c = RTCIceCandidate(s.data['candidate'] as String?,
              s.data['sdpMid'] as String?, s.data['sdpMLineIndex'] as int?);
          final pc = _pcs[s.from];
          if (pc == null || await pc.getRemoteDescription() == null) {
            _pendingIce.putIfAbsent(s.from, () => []).add(c);
          } else {
            await pc.addCandidate(c);
          }
      }
    } catch (_) {
      _set(s.from, PeerVoice.failed);
    }
  }

  Future<void> _flushIce(int seat) async {
    final pc = _pcs[seat];
    final list = _pendingIce.remove(seat);
    if (pc == null || list == null) return;
    for (final c in list) {
      await pc.addCandidate(c);
    }
  }

  Future<void> _hangUp(int seat) async {
    final pc = _pcs.remove(seat);
    _pendingIce.remove(seat);
    _set(seat, null);
    await pc?.close();
  }

  void toggleMute() {
    muted.value = !muted.value;
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted.value;
    }
  }

  Future<void> toggleSpeaker() async {
    speaker.value = !speaker.value;
    await Helper.setSpeakerphoneOn(speaker.value).catchError((_) {});
  }

  Future<void> close() async {
    _closed = true;
    await _signals?.cancel();
    await _room?.cancel();
    for (final s in _pcs.keys.toList()) {
      await _hangUp(s);
    }
    for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    _mic = null;
  }
}
