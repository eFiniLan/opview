// Cereal adapter implementation
// Parses individual cereal messages from webrtcd

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:opview/services/adapter.dart';
import 'package:opview/selfdrive/ui/ui_state.dart';

// pre-compiled regex for NaN replacement
final _nanRegex = RegExp(r'\bNaN\b');

// max buffer size before forced reset (prevents unbounded growth from malformed data)
const _maxBufferSize = 256 * 1024; // 256 KB

class CerealAdapter implements TelemetryAdapter {
  final _buffer = StringBuffer();

  @override
  bool apply(UIState state, String rawMessage) {
    if (_buffer.length + rawMessage.length > _maxBufferSize) {
      debugPrint('[opview] buffer overflow (${_buffer.length + rawMessage.length} bytes), dropping malformed data');
      _buffer.clear();
      return false;
    }
    _buffer.write(rawMessage);
    bool didUpdate = false;

    // split on }{ boundaries (concatenated JSON objects)
    var s = _buffer.toString();
    int boundary;
    while ((boundary = s.indexOf('}{')) != -1) {
      final jsonString = s.substring(0, boundary + 1);
      if (_tryApply(state, jsonString)) {
        didUpdate = true;
      }
      s = s.substring(boundary + 1);
    }

    // try remaining buffer if it looks complete
    if (s.isNotEmpty && s.trimRight().endsWith('}')) {
      if (_tryApply(state, s)) {
        didUpdate = true;
      }
      s = '';
    }

    _buffer.clear();
    if (s.isNotEmpty) _buffer.write(s);

    return didUpdate;
  }

  bool _tryApply(UIState state, String raw) {
    try {
      final sanitized = raw.contains('NaN') ? raw.replaceAll(_nanRegex, 'null') : raw;
      final json = jsonDecode(sanitized) as Map<String, dynamic>;
      final type = json['type'] as String?;
      final data = json['data'] as Map<String, dynamic>?;

      if (type == null || data == null) return false;

      return _dispatch(state, type, data);
    } catch (_) {
      return false;
    }
  }

  bool _dispatch(UIState state, String type, Map<String, dynamic> data) {
    switch (type) {
      case 'carState':
        state.applyCarState(data);
        return false; // don't notify yet
      case 'selfdriveState':
        state.applySelfdriveState(data);
        return false;
      case 'controlsState':
        state.applyControlsState(data);
        return false;
      case 'modelV2':
        state.applyModelV2(data);
        return true; // modelV2 triggers render
      case 'liveCalibration':
        state.applyLiveCalibration(data);
        return false;
      case 'radarState':
        state.applyRadarState(data);
        return false;
      case 'longitudinalPlan':
        state.applyLongitudinalPlan(data);
        return false;
      case 'deviceState':
        state.applyDeviceState(data);
        return false;
      case 'roadCameraState':
        state.applyRoadCameraState(data);
        return false;
      default:
        return false;
    }
  }

  @override
  void reset() {
    _buffer.clear();
  }
}
