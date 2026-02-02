// connection manager — the orchestrator
// discover → connect → parse → apply to UIState
//
// one class ties it all together:
//   1. discover comma device via mDNS
//   2. connect WebRTC (video + data channel)
//   3. parse incoming telemetry
//   4. dispatch to UIState
//   5. reconnect on failure with exponential backoff

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:scope/selfdrive/ui/ui_state.dart';
import 'package:scope/system/webrtc/webrtc_client.dart';
import 'package:scope/services/discovery_service.dart';
import 'package:scope/services/telemetry_parser.dart';
import 'package:scope/services/wake_lock_service.dart' as wake_lock;

// backoff config (webrtc.js:16-18)
const _retryInitialDelay = Duration(seconds: 2);
const _retryMaxDelay = Duration(seconds: 10);
const _retryMultiplier = 2;
const _watchdogTimeout = Duration(seconds: 5);

// delay before re-discovery after all retries exhausted
const _rediscoverDelay = Duration(seconds: 15);

// camera switching thresholds (augmented_road_view.py:29-30)
const wideCamMaxSpeed = 10.0;  // m/s — switch to wide below this
const roadCamMinSpeed = 15.0;  // m/s — switch to road above this

class ConnectionManager {
  final UIState _uiState;
  final DiscoveryService _discovery = DiscoveryService();
  final WebRTCClient _client = WebRTCClient();
  final TelemetryParser _parser = TelemetryParser();

  RTCVideoRenderer get videoRenderer => _client.videoRenderer;

  String? _host;
  StreamSubscription? _deviceSub;
  StreamSubscription? _dataSub;
  StreamSubscription? _stateSub;
  Timer? _watchdog;
  Timer? _retryTimer;
  Duration _retryDelay = _retryInitialDelay;
  DateTime _lastDataTime = DateTime.now();
  bool _connecting = false;
  bool _paused = false;
  bool _reconnecting = false;  // guard against re-entrant _scheduleReconnect
  int _connectEpoch = 0;       // invalidate stale in-flight connects
  int _retryCount = 0;
  static const _maxRetries = 3;
  String _streamType = 'road';

  ConnectionManager(this._uiState);

  /// start discovery + auto-connect
  void start() {
    _uiState.startThrottle();
    _startDiscovery();
  }

  void _startDiscovery() {
    _deviceSub?.cancel();
    _deviceSub = _discovery.devices.listen(_onDeviceFound);
    _discovery.start();
  }

  /// first device found → connect
  void _onDeviceFound(device) {
    if (_host != null) return; // already connecting to one
    _host = device.host;
    debugPrint('[scope] discovered ${device.displayName} at ${device.host}');
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
      debugPrint('[scope] connecting to $_host (camera: $_streamType)');
      await _client.connect(_host!, camera: _streamType);
      if (epoch != _connectEpoch) return; // superseded by newer connect
      _retryDelay = _retryInitialDelay;
      _retryCount = 0;
      _lastDataTime = DateTime.now();
      _listenData();
      _listenState();
      _startWatchdog();
      if (_uiState.isSwitchingStream) {
        _uiState.isSwitchingStream = false;
        _uiState.markDirty();
      }
      _setConnected(true);
      debugPrint('[scope] connected');
    } catch (e) {
      if (epoch != _connectEpoch) return; // superseded, don't reconnect
      debugPrint('[scope] connection failed: $e');
      _scheduleReconnect();
    } finally {
      if (epoch == _connectEpoch) _connecting = false;
    }
  }

  /// listen to data channel → parse → dispatch
  void _listenData() {
    _dataSub?.cancel();
    _dataSub = _client.dataStream.listen((chunk) {
      _lastDataTime = DateTime.now();
      final messages = _parser.parse(chunk);
      for (final msg in messages) {
        _dispatch(msg.type, msg.data);
      }
    });
  }

  /// dispatch parsed message to the right UIState apply method
  void _dispatch(String type, dynamic data) {
    if (data is! Map<String, dynamic>) return;
    switch (type) {
      case 'carState':
        _uiState.applyCarState(data);
        _switchStreamIfNeeded();
      case 'selfdriveState':
        _uiState.applySelfdriveState(data);
        _switchStreamIfNeeded();
      case 'controlsState': _uiState.applyControlsState(data);
      case 'modelV2': _uiState.applyModelV2(data);
      case 'liveCalibration': _uiState.applyLiveCalibration(data);
      case 'radarState': _uiState.applyRadarState(data);
      case 'longitudinalPlan': _uiState.applyLongitudinalPlan(data);
      case 'deviceState': _uiState.applyDeviceState(data);
      case 'roadCameraState': _uiState.applyRoadCameraState(data);
    }
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
    _uiState.markDirty();
    debugPrint('[scope] camera switch → $_streamType');
    // immediate reconnect — no backoff, no retry counting
    _teardown();
    _retryDelay = _retryInitialDelay;
    _retryCount = 0;
    _connect();
  }

  /// listen for connection state → reconnect on failure
  void _listenState() {
    _stateSub?.cancel();
    _stateSub = _client.stateStream.listen((state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        debugPrint('[scope] connection lost: $state');
        _scheduleReconnect();
      }
    });
  }

  /// watchdog: reconnect if no data for 5 seconds
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (DateTime.now().difference(_lastDataTime) > _watchdogTimeout) {
        debugPrint('[scope] data stalled, reconnecting');
        _scheduleReconnect();
      }
    });
  }

  /// update connection state + toggle screen wake lock
  void _setConnected(bool connected) {
    if (_uiState.isConnected == connected) return;
    _uiState.isConnected = connected;
    _uiState.markDirty();
    wake_lock.setKeepScreenOn(connected);
  }

  /// cancel all timers and subscriptions (but keep _host and _deviceSub)
  void _teardown() {
    _connectEpoch++;  // invalidate any in-flight _client.connect()
    _watchdog?.cancel();
    _retryTimer?.cancel();
    _dataSub?.cancel();
    _stateSub?.cancel();
    _stateSub = null;
    _parser.reset();
    _connecting = false;
    _reconnecting = false;
    _client.close();  // close current PC immediately
  }

  /// exponential backoff reconnect, fall back to re-discovery after max retries
  void _scheduleReconnect() {
    // prevent re-entrant calls (state listener + catch block firing together)
    if (_reconnecting || _paused) return;
    _reconnecting = true;

    _watchdog?.cancel();
    _retryTimer?.cancel();
    _dataSub?.cancel();
    _stateSub?.cancel();
    _stateSub = null;
    _parser.reset();
    _setConnected(false);

    _retryCount++;

    if (_retryCount > _maxRetries) {
      // give up on this host, wait then re-discover
      if (_uiState.isSwitchingStream) {
        _uiState.isSwitchingStream = false;
        _uiState.markDirty();
      }
      debugPrint('[scope] $_maxRetries retries failed, waiting ${_rediscoverDelay.inSeconds}s before re-discovery');
      _host = null;
      _retryCount = 0;
      _retryDelay = _retryInitialDelay;
      _retryTimer = Timer(_rediscoverDelay, () {
        if (_paused) return;
        _reconnecting = false;
        _startDiscovery();
      });
      return;
    }

    debugPrint('[scope] retry $_retryCount/$_maxRetries in ${_retryDelay.inSeconds}s');
    _retryTimer = Timer(_retryDelay, () {
      _retryDelay = Duration(
        milliseconds: (_retryDelay.inMilliseconds * _retryMultiplier)
          .clamp(0, _retryMaxDelay.inMilliseconds),
      );
      _reconnecting = false;
      _connect();
    });
  }

  /// stop all activity — call when app goes to background
  void pause() {
    if (_paused) return;
    _paused = true;
    debugPrint('[scope] paused');
    _teardown();
  }

  /// tear down current connection and reconnect (or re-discover)
  void reconnect() {
    _paused = false;
    debugPrint('[scope] reconnect requested');
    _teardown();
    _retryCount = 0;
    _retryDelay = _retryInitialDelay;

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
    await _client.dispose();
  }
}
