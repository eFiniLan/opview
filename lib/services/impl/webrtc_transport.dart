// WebRTC transport implementation
// Connects to webrtcd for video + data channel

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:opview/services/transport.dart';
import 'package:opview/system/webrtc/webrtc_client.dart';

class WebRTCTransport implements Transport {
  final WebRTCClient _client = WebRTCClient();
  final _stateController = StreamController<TransportState>.broadcast();

  StreamSubscription? _clientStateSub;

  @override
  Stream<String> get dataStream => _client.dataStream;

  @override
  Stream<TransportState> get stateStream => _stateController.stream;

  @override
  dynamic get videoRenderer => _client.videoRenderer;

  @override
  Future<void> connect(String host, {String camera = 'road'}) async {
    // Listen to WebRTC connection state and translate to TransportState
    _clientStateSub?.cancel();
    _clientStateSub = _client.stateStream.listen((state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _stateController.add(TransportState.connecting);
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _stateController.add(TransportState.connected);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _stateController.add(TransportState.failed);
        default:
          break;
      }
    });

    await _client.connect(host, camera: camera);
  }

  @override
  Future<void> close() async {
    _clientStateSub?.cancel();
    _clientStateSub = null;
    await _client.close();
  }

  @override
  Future<void> dispose() async {
    _clientStateSub?.cancel();
    await _client.dispose();
    await _stateController.close();
  }
}
