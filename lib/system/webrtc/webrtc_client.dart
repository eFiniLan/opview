// WebRTC client — PeerConnection, data channel, H264 preference
// ported from dashy web/src/js/core/webrtc.js
//
// creates a recvonly video connection with a data channel.
// H264 preferred for hardware decode on mobile.
// exposes video renderer + raw data stream.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:scope/system/webrtc/webrtcd_api.dart';

class WebRTCClient {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  final RTCVideoRenderer videoRenderer = RTCVideoRenderer();
  int _connectGen = 0; // generation counter — stale connects bail out

  // data channel messages as a stream
  final _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  // connection state
  final _stateController = StreamController<RTCPeerConnectionState>.broadcast();
  Stream<RTCPeerConnectionState> get stateStream => _stateController.stream;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await videoRenderer.initialize();
    _initialized = true;
  }

  /// connect to webrtcd on the given host
  /// only one connection at a time — newer connect() cancels any in-flight one
  Future<void> connect(String host, {String camera = 'road'}) async {
    final gen = ++_connectGen;
    await init();
    await _cleanup();
    if (gen != _connectGen) return; // superseded by newer connect

    // create peer connection — no ICE servers needed for LAN
    _pc = await createPeerConnection({'iceServers': []});

    // data channel for cereal messages
    _dataChannel = await _pc!.createDataChannel('data', RTCDataChannelInit());
    _setupDataChannel(_dataChannel!);

    // also handle server-created data channel (fallback)
    _pc!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannel(channel);
    };

    // video: recvonly
    _pc!.onTrack = (event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        videoRenderer.srcObject = event.streams[0];
      }
    };

    // connection state changes — ignore if superseded
    _pc!.onConnectionState = (state) {
      if (gen == _connectGen) _stateController.add(state);
    };

    // add recvonly video transceiver
    await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    // create offer, prefer H264
    final offer = await _pc!.createOffer();
    if (gen != _connectGen) return;
    offer.sdp = preferH264(offer.sdp!);
    await _pc!.setLocalDescription(offer);
    if (gen != _connectGen) return;

    // exchange SDP with webrtcd
    final answer = await postStream(host, offer.sdp!, camera: camera);
    if (gen != _connectGen) return;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
    );
  }

  /// close current connection without disposing renderer
  Future<void> close() {
    _connectGen++; // invalidate any in-flight connect
    return _cleanup();
  }

  /// listen on data channel for cereal messages
  void _setupDataChannel(RTCDataChannel dc) {
    dc.onMessage = (msg) {
      try {
        final text = msg.isBinary ? utf8.decode(msg.binary) : msg.text;
        if (text.isNotEmpty) {
          _dataController.add(text);
        }
      } catch (_) {}
    };
  }

  Future<void> _cleanup() async {
    // grab + null references first so concurrent calls no-op
    final pc = _pc;
    final dc = _dataChannel;
    _pc = null;
    _dataChannel = null;
    videoRenderer.srcObject = null;
    dc?.close();
    await pc?.close();
  }

  Future<void> dispose() async {
    _connectGen++;
    await _cleanup();
    await videoRenderer.dispose();
    await _dataController.close();
    await _stateController.close();
  }
}

// -- SDP rewriting (webrtc.js:302-337) --

/// reorder SDP to prefer H264 over VP8/VP9
String preferH264(String sdp) {
  final lines = sdp.split('\r\n');
  int mLineIndex = -1;
  final h264Payloads = <String>[];

  // find m=video line and H264 payload types
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('m=video')) {
      mLineIndex = i;
    } else if (lines[i].contains('H264/90000')) {
      final match = RegExp(r'a=rtpmap:(\d+) H264/90000').firstMatch(lines[i]);
      if (match != null) h264Payloads.add(match.group(1)!);
    }
  }

  if (mLineIndex == -1 || h264Payloads.isEmpty) return sdp;

  // find associated RTX payloads (apt= and rtpmap are on separate SDP lines)
  // step 1: collect all rtx payload types
  final rtxMap = <String, String>{}; // rtx payload → apt payload
  for (final line in lines) {
    final fmtp = RegExp(r'a=fmtp:(\d+) apt=(\d+)').firstMatch(line);
    if (fmtp != null) rtxMap[fmtp.group(1)!] = fmtp.group(2)!;
  }
  // step 2: keep only rtx payloads that point to our H264 payloads
  final rtxPayloads = <String>[];
  for (final entry in rtxMap.entries) {
    if (h264Payloads.contains(entry.value)) {
      // verify it's actually rtx/90000
      final isRtx = lines.any((l) => l.contains('a=rtpmap:${entry.key} rtx/90000'));
      if (isRtx) rtxPayloads.add(entry.key);
    }
  }

  // reorder m-line: H264 payloads first
  final allH264 = [...h264Payloads, ...rtxPayloads];
  final parts = lines[mLineIndex].split(' ');
  final others = parts.sublist(3).where((p) => !allH264.contains(p));
  lines[mLineIndex] = [...parts.sublist(0, 3), ...allH264, ...others].join(' ');

  return lines.join('\r\n');
}
