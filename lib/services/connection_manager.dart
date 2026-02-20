// connection manager — the orchestrator
// discover → connect → parse → apply to UIState
//
// one class ties it all together:
//   1. discover comma device via mDNS
//   2. connect WebRTC (video + data channel)
//   3. parse incoming telemetry via adapter
//   4. dispatch to UIState
//   5. reconnect on failure

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:opview/selfdrive/ui/ui_state.dart';
import 'package:opview/services/discovery.dart';
import 'package:opview/services/transport.dart';
import 'package:opview/services/adapter.dart';
import 'package:opview/services/impl/mdns_discovery.dart';
import 'package:opview/services/impl/webrtc_transport.dart';
import 'package:opview/services/impl/cereal_adapter.dart';
import 'package:opview/services/wake_lock_service.dart' as wake_lock;

// fallback IP if discovery fails (for debugging)
const _fallbackIp = '192.168.0.52';
const _discoveryTimeout = Duration(seconds: 5);

// retry config
const _retryDelay = Duration(seconds: 2);

// delay before re-discovery after all retries exhausted
const _rediscoverDelay = Duration(seconds: 15);

// camera switching thresholds (augmented_road_view.py:29-30)
const wideCamMaxSpeed = 10.0;  // m/s — switch to wide below this
const roadCamMinSpeed = 15.0;  // m/s — switch to road above this

class ConnectionManager {
  final UIState _uiState;
  final Discovery _discovery;
  final Transport _transport;
  final TelemetryAdapter _adapter;

  dynamic get videoRenderer => _transport.videoRenderer;

  ConnectionManager(
    this._uiState, {
    Discovery? discovery,
    Transport? transport,
    TelemetryAdapter? adapter,
  })  : _discovery = discovery ?? MdnsDiscovery(),
        _transport = transport ?? WebRTCTransport(),
        _adapter = adapter ?? CerealAdapter();

  String? _host;
  StreamSubscription? _deviceSub;
  StreamSubscription? _dataSub;
  StreamSubscription? _stateSub;
  Timer? _retryTimer;
  Timer? _discoveryTimer;
  bool _connecting = false;
  bool _paused = false;
  bool _reconnecting = false;  // guard against re-entrant _scheduleReconnect
  int _connectEpoch = 0;       // invalidate stale in-flight connects
  int _retryCount = 0;
  static const _maxRetries = 3;
  String _streamType = 'road';

  /// start discovery + auto-connect
  void start() {
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    _deviceSub?.cancel();
    _discoveryTimer?.cancel();
    _deviceSub = _discovery.devices.listen(_onDeviceFound);
    await _discovery.start();

    // fallback to debug IP if discovery times out (debug builds only)
    if (kDebugMode) {
      _discoveryTimer = Timer(_discoveryTimeout, () {
        if (_host != null || _paused) return;
        debugPrint('[opview] discovery timeout, falling back to $_fallbackIp');
        _discovery.stop();
        _host = _fallbackIp;
        _connect();
      });
    }
  }

  /// first device found → connect
  void _onDeviceFound(DiscoveredDevice device) {
    if (_host != null) return; // already connecting to one
    _discoveryTimer?.cancel();
    _host = device.host;
    debugPrint('[opview] discovered ${device.displayName} at ${device.host}');
    _discovery.stop(); // stop discovery, we have our target
    _connect();
  }

  Future<void> _connect() async {
    if (_connecting || _host == null || _paused) return;
    _connecting = true;
    _reconnecting = false;
    final epoch = ++_connectEpoch;

    // cancel stale listeners before attempting new connection
    _stateSub?.cancel();
    _stateSub = null;

    try {
      debugPrint('[opview] connecting to $_host (camera: $_streamType)');
      await _transport.connect(_host!, camera: _streamType);
      if (epoch != _connectEpoch) return; // superseded by newer connect
      _retryCount = 0;
      _listenData();
      _listenState();
      if (_uiState.isSwitchingStream) {
        _uiState.isSwitchingStream = false;
        _uiState.notifyNow();
      }
      _setConnected(true);
      debugPrint('[opview] connected');
    } catch (e) {
      if (epoch != _connectEpoch) return; // superseded, don't reconnect
      debugPrint('[opview] connection failed: $e');
      _scheduleReconnect();
    } finally {
      if (epoch == _connectEpoch) _connecting = false;
    }
  }

  /// listen to data channel → adapter → UIState
  void _listenData() {
    _dataSub?.cancel();
    _dataSub = _transport.dataStream.listen((chunk) {
      _adapter.apply(_uiState, chunk);
      _switchStreamIfNeeded();
    });
  }

  /// switch camera based on experimental mode + speed hysteresis
  /// (augmented_road_view.py:122-136)
  void _switchStreamIfNeeded() {
    String target;
    if (_uiState.experimentalMode) {
      final vEgo = _uiState.vEgo;
      if (vEgo < wideCamMaxSpeed) {
        target = 'wideRoad';
      } else if (vEgo > roadCamMinSpeed) {
        target = 'road';
      } else {
        // hysteresis zone — keep current
        return;
      }
    } else {
      target = 'road';
    }
    if (target == _streamType) return;
    _streamType = target;
    _uiState.streamType = target;
    _uiState.isSwitchingStream = true;
    _uiState.notifyNow();
    debugPrint('[opview] camera switch → $_streamType');
    // immediate reconnect — no retry counting
    _teardown();
    _retryCount = 0;
    _connect();
  }

  /// listen for connection state → reconnect on failure
  void _listenState() {
    _stateSub?.cancel();
    _stateSub = _transport.stateStream.listen((state) {
      if (state == TransportState.failed) {
        debugPrint('[opview] connection lost');
        _scheduleReconnect();
      }
    });
  }

  /// update connection state + toggle screen wake lock
  void _setConnected(bool connected) {
    if (_uiState.isConnected == connected) return;
    _uiState.isConnected = connected;
    _uiState.notifyNow();
    wake_lock.setKeepScreenOn(connected);
  }

  /// cancel all timers and subscriptions (but keep _host and _deviceSub)
  void _teardown() {
    _connectEpoch++;  // invalidate any in-flight _transport.connect()
    _retryTimer?.cancel();
    _discoveryTimer?.cancel();
    _dataSub?.cancel();
    _stateSub?.cancel();
    _stateSub = null;
    _adapter.reset();
    _connecting = false;
    _reconnecting = false;
    _transport.close();  // close current connection immediately
  }

  /// exponential backoff reconnect, fall back to re-discovery after max retries
  void _scheduleReconnect() {
    // prevent re-entrant calls (state listener + catch block firing together)
    if (_reconnecting || _paused) return;
    _reconnecting = true;

    _retryTimer?.cancel();
    _dataSub?.cancel();
    _stateSub?.cancel();
    _stateSub = null;
    _adapter.reset();
    _transport.close();  // free server-side session
    _setConnected(false);

    _retryCount++;

    if (_retryCount > _maxRetries) {
      // give up on this host, wait then re-discover
      if (_uiState.isSwitchingStream) {
        _uiState.isSwitchingStream = false;
        _uiState.notifyNow();
      }
      debugPrint('[opview] $_maxRetries retries failed, waiting ${_rediscoverDelay.inSeconds}s before re-discovery');
      _host = null;
      _retryCount = 0;
      _retryTimer = Timer(_rediscoverDelay, () {
        if (_paused) return;
        _reconnecting = false;
        _startDiscovery();
      });
      return;
    }

    debugPrint('[opview] retry $_retryCount/$_maxRetries in ${_retryDelay.inSeconds}s');
    _retryTimer = Timer(_retryDelay, () {
      _reconnecting = false;
      _connect();
    });
  }

  /// stop all activity — call when app goes to background
  void pause() {
    if (_paused) return;
    _paused = true;
    debugPrint('[opview] paused');
    _teardown();
  }

  /// tear down current connection and reconnect (or re-discover)
  void reconnect() {
    _paused = false;
    debugPrint('[opview] reconnect requested');
    _teardown();
    _retryCount = 0;

    if (_host != null) {
      _connect();
    } else {
      _startDiscovery();
    }
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    _teardown();
    _deviceSub?.cancel();
    _discovery.dispose();
    await _transport.dispose();
  }
}
