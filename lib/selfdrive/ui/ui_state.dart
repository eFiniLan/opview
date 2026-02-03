// UI state — the single source of truth
// ported from openpilot selfdrive/ui/ui_state.py
//
// one ChangeNotifier, fed by telemetry parser.
// data-driven refresh: notifyListeners on modelV2 arrival.

import 'package:flutter/foundation.dart';

// -- constants --

const uiBorderSize = 30;
const setSpeedNA = 255;
const kmToMile = 0.621371;
const msToKph = 3.6;
const msToMph = 2.23694;

// -- engagement status (matches ui_state.py UIStatus) --

enum UIStatus { disengaged, engaged, override_ }

// -- state --

class UIState extends ChangeNotifier {
  // engagement
  UIStatus status = UIStatus.disengaged;
  bool started = false;

  // carState
  double vEgo = 0.0;
  double vEgoCluster = 0.0;
  double vCruiseCluster = 0.0;
  bool vEgoClusterSeen = false;

  // selfdriveState
  bool enabled = false;
  bool experimentalMode = false;
  String alertText1 = '';
  String alertText2 = '';
  int alertSize = 0;     // 0=none, 1=small, 2=mid, 3=full
  int alertStatus = 0;   // 0=normal, 1=userPrompt, 2=critical
  String openpilotState = '';

  // controlsState
  double vCruiseDEPRECATED = 0.0;

  // modelV2 — raw lists from cereal
  List<double> pathX = [];
  List<double> pathY = [];
  List<double> pathZ = [];
  List<List<double>> laneLineX = [[], [], [], []];
  List<List<double>> laneLineY = [[], [], [], []];
  List<List<double>> laneLineZ = [[], [], [], []];
  List<double> laneLineProbs = [0, 0, 0, 0];
  List<List<double>> roadEdgeX = [[], []];
  List<List<double>> roadEdgeY = [[], []];
  List<List<double>> roadEdgeZ = [[], []];
  List<double> roadEdgeStds = [0, 0];
  List<double> accelerationX = [];

  // liveCalibration
  List<double> rpyCalib = [];
  List<double> wideFromDeviceEuler = [];
  String calStatus = '';
  List<double> calibHeight = [];

  // radarState
  Map<String, dynamic>? leadOne;
  Map<String, dynamic>? leadTwo;

  // longitudinalPlan
  bool allowThrottle = true;

  // deviceState / roadCameraState — for camera intrinsics lookup
  String deviceType = '';
  String sensor = '';

  // is_metric (default true, like stock)
  bool isMetric = true;

  // active camera: 'road' or 'wideRoad' (switches on experimental mode)
  String streamType = 'road';

  // true while reconnecting for a camera switch (drives fade animation)
  bool isSwitchingStream = false;

  // connection state — drives "Connecting..." overlay + screen wake lock
  bool isConnected = false;

  /// monotonic version counter — incremented on each notify.
  /// used by painters to detect state changes in shouldRepaint.
  int version = 0;

  /// notify listeners and bump version
  void _notify() {
    version++;
    notifyListeners();
  }

  /// force immediate notify (for connection state changes)
  void notifyNow() {
    _notify();
  }

  // -- apply methods: one per cereal service --

  void applyCarState(Map<String, dynamic> data) {
    vEgo = (data['vEgo'] as num?)?.toDouble() ?? 0.0;
    vEgoCluster = (data['vEgoCluster'] as num?)?.toDouble() ?? 0.0;
    vCruiseCluster = (data['vCruiseCluster'] as num?)?.toDouble() ?? 0.0;
    if (!vEgoClusterSeen && vEgoCluster != 0.0) vEgoClusterSeen = true;
    // no notify — picked up on next modelV2
  }

  void applySelfdriveState(Map<String, dynamic> data) {
    enabled = data['enabled'] as bool? ?? false;
    experimentalMode = data['experimentalMode'] as bool? ?? false;
    alertText1 = data['alertText1'] as String? ?? '';
    alertText2 = data['alertText2'] as String? ?? '';
    alertSize = _alertSizeFromString(data['alertSize']);
    alertStatus = _alertStatusFromString(data['alertStatus']);
    openpilotState = data['state'] as String? ?? '';

    // update engagement status
    started = true;
    if (openpilotState == 'preEnabled' || openpilotState == 'overriding') {
      status = UIStatus.override_;
    } else {
      status = enabled ? UIStatus.engaged : UIStatus.disengaged;
    }
    // no notify — picked up on next modelV2
  }

  void applyControlsState(Map<String, dynamic> data) {
    vCruiseDEPRECATED = (data['vCruiseDEPRECATED'] as num?)?.toDouble() ?? 0.0;
    // no notify — picked up on next modelV2
  }

  void applyModelV2(Map<String, dynamic> data) {
    pathX = _toDoubles(data['position']?['x']);
    pathY = _toDoubles(data['position']?['y']);
    pathZ = _toDoubles(data['position']?['z']);

    final lanes = data['laneLines'] as List? ?? [];
    for (int i = 0; i < 4 && i < lanes.length; i++) {
      laneLineX[i] = _toDoubles(lanes[i]['x']);
      laneLineY[i] = _toDoubles(lanes[i]['y']);
      laneLineZ[i] = _toDoubles(lanes[i]['z']);
    }
    laneLineProbs = _toDoublesFixed(_toDoubles(data['laneLineProbs']), 4);

    final edges = data['roadEdges'] as List? ?? [];
    for (int i = 0; i < 2 && i < edges.length; i++) {
      roadEdgeX[i] = _toDoubles(edges[i]['x']);
      roadEdgeY[i] = _toDoubles(edges[i]['y']);
      roadEdgeZ[i] = _toDoubles(edges[i]['z']);
    }
    roadEdgeStds = _toDoublesFixed(_toDoubles(data['roadEdgeStds']), 2);
    accelerationX = _toDoubles(data['acceleration']?['x']);
    _notify();  // data-driven: render on modelV2 arrival
  }

  void applyLiveCalibration(Map<String, dynamic> data) {
    rpyCalib = _toDoubles(data['rpyCalib']);
    wideFromDeviceEuler = _toDoubles(data['wideFromDeviceEuler']);
    calStatus = data['calStatus'] as String? ?? '';
    calibHeight = _toDoubles(data['height']);
    // no notify — picked up on next modelV2
  }

  void applyRadarState(Map<String, dynamic> data) {
    leadOne = data['leadOne'] as Map<String, dynamic>?;
    leadTwo = data['leadTwo'] as Map<String, dynamic>?;
    // no notify — picked up on next modelV2
  }

  void applyLongitudinalPlan(Map<String, dynamic> data) {
    allowThrottle = data['allowThrottle'] as bool? ?? true;
    // no notify — picked up on next modelV2
  }

  void applyDeviceState(Map<String, dynamic> data) {
    deviceType = data['deviceType'] as String? ?? '';
    started = data['started'] as bool? ?? started;
    // no notify — picked up on next modelV2
  }

  void applyRoadCameraState(Map<String, dynamic> data) {
    sensor = data['sensor'] as String? ?? '';
    // no notify — picked up on next modelV2
  }

  // -- derived values --

  /// display speed in current unit (km/h or mph)
  double get displaySpeed {
    final v = vEgoClusterSeen ? vEgoCluster : vEgo;
    final conv = isMetric ? msToKph : msToMph;
    final s = v * conv;
    return s > 0 ? s : 0;
  }

  /// raw cruise speed in kph (before unit conversion)
  double get _rawSetSpeed => vCruiseCluster != 0.0 ? vCruiseCluster : vCruiseDEPRECATED;

  /// is cruise actively set
  bool get isCruiseSet => _rawSetSpeed > 0 && _rawSetSpeed < setSpeedNA;

  /// cruise set speed in current unit
  double get setSpeed {
    final s = _rawSetSpeed;
    if (!isCruiseSet) return s;
    return isMetric ? s : s * kmToMile;
  }

  /// is cruise available (not -1)
  bool get isCruiseAvailable => _rawSetSpeed != -1;

  // -- helpers --

  List<double> _toDoubles(dynamic list) {
    if (list == null) return [];
    if (list is List) return list.map((e) => (e as num?)?.toDouble() ?? 0.0).toList();
    return [];
  }

  /// ensure list has exactly [n] elements, padding with 0.0 or truncating
  List<double> _toDoublesFixed(List<double> list, int n) {
    if (list.length == n) return list;
    if (list.length > n) return list.sublist(0, n);
    return [...list, ...List.filled(n - list.length, 0.0)];
  }

  int _alertSizeFromString(dynamic v) {
    if (v is int) return v;
    if (v is String) {
      switch (v) {
        case 'none': return 0;
        case 'small': return 1;
        case 'mid': return 2;
        case 'full': return 3;
      }
    }
    return 0;
  }

  int _alertStatusFromString(dynamic v) {
    if (v is int) return v;
    if (v is String) {
      switch (v) {
        case 'normal': return 0;
        case 'userPrompt': return 1;
        case 'critical': return 2;
      }
    }
    return 0;
  }

  @override
  void dispose() {
    super.dispose();
  }
}
