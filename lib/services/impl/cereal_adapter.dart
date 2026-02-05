// Cereal adapter implementation
// Parses individual cereal messages from webrtcd

import 'dart:convert';
import 'package:opview/services/adapter.dart';
import 'package:opview/selfdrive/ui/ui_state.dart';

// pre-compiled regex for NaN replacement
final _nanRegex = RegExp(r'\bNaN\b');

class CerealAdapter implements TelemetryAdapter {
  String _buffer = '';

  @override
  bool apply(UIState state, String rawMessage) {
    _buffer += rawMessage;
    bool didUpdate = false;

    // split on }{ boundaries (concatenated JSON objects)
    int boundary;
    while ((boundary = _buffer.indexOf('}{')) != -1) {
      final jsonString = _buffer.substring(0, boundary + 1);
      if (_tryApply(state, jsonString)) {
        didUpdate = true;
      }
      _buffer = _buffer.substring(boundary + 1);
    }

    // try remaining buffer if it looks complete
    if (_buffer.isNotEmpty && _buffer.trimRight().endsWith('}')) {
      if (_tryApply(state, _buffer)) {
        didUpdate = true;
      }
      _buffer = '';
    }

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
    _buffer = '';
  }
}
