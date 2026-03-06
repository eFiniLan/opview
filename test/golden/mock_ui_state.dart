// Mock UIState with realistic openpilot telemetry data for golden tests

import 'dart:math';
import 'package:opview/selfdrive/ui/ui_state.dart';

/// Create a UIState populated with realistic driving data
UIState createMockUIState({
  double vEgo = 18.0,           // ~65 km/h
  double vCruiseCluster = 80.0, // cruise set at 80 km/h
  bool engaged = true,
  bool experimentalMode = false,
  double leadDRel = 30.0,       // lead car 30m ahead
  String alertText1 = '',
  String alertText2 = '',
  int alertSize = 0,
  int alertStatus = 0,
  bool calibrating = false,
}) {
  final state = UIState();

  // connection
  state.isConnected = true;

  // car state
  state.vEgo = vEgo;
  state.vEgoCluster = vEgo;
  state.vEgoClusterSeen = true;
  state.vCruiseCluster = vCruiseCluster;

  // selfdrive state
  state.enabled = engaged;
  state.started = true;
  state.experimentalMode = experimentalMode;
  state.status = engaged ? UIStatus.engaged : UIStatus.disengaged;
  state.alertText1 = alertText1;
  state.alertText2 = alertText2;
  state.alertSize = alertSize;
  state.alertStatus = alertStatus;

  // calibration
  if (calibrating) {
    state.rpyCalib = [];
    state.wideFromDeviceEuler = [];
    state.calStatus = 'uncalibrated';
    state.calibHeight = [];
  } else {
    state.rpyCalib = [0.0, 0.015, 0.005]; // roll, pitch, yaw in radians
    state.wideFromDeviceEuler = [0.0, 0.0, 0.0];
    state.calStatus = 'calibrated';
    state.calibHeight = [1.22]; // typical camera height
  }

  // device
  state.deviceType = 'tici';
  state.sensor = 'ar0231';
  state.streamType = 'road';

  // longitudinal
  state.allowThrottle = true;

  // generate path — gentle right curve
  _generatePath(state);

  // generate lane lines
  _generateLaneLines(state);

  // generate road edges
  _generateRoadEdges(state);

  // acceleration
  state.accelerationX = List.generate(33, (i) => 0.5 - i * 0.02);

  // lead vehicle
  if (leadDRel > 0) {
    state.leadOne = {
      'status': true,
      'dRel': leadDRel,
      'yRel': -0.5,
      'vRel': -2.0,
    };
  }

  return state;
}

/// Generate realistic path points — gentle curve ahead
void _generatePath(UIState state) {
  const n = 33; // typical model output length
  state.pathX = List.generate(n, (i) => i * 3.0);          // 0 to ~100m
  state.pathY = List.generate(n, (i) => sin(i * 0.05) * 1.5); // gentle curve
  state.pathZ = List.generate(n, (i) => -0.02 * i);        // slight downhill
}

/// Generate 4 lane lines at typical offsets
void _generateLaneLines(UIState state) {
  const n = 33;
  final offsets = [-3.6, -1.8, 1.8, 3.6]; // meters from center

  state.laneLineX = List.generate(4, (_) => List.generate(n, (i) => i * 3.0));
  state.laneLineY = List.generate(4, (li) =>
    List.generate(n, (i) => offsets[li] + sin(i * 0.05) * 1.5));
  // Z in device frame (z-down): ~calibHeight = road surface below camera
  state.laneLineZ = List.generate(4, (_) =>
    List.generate(n, (i) => 1.22 - 0.02 * i));
  state.laneLineProbs = [0.8, 0.95, 0.95, 0.8]; // inner lanes more confident
}

/// Generate 2 road edges at typical offsets
void _generateRoadEdges(UIState state) {
  const n = 33;
  final offsets = [-5.5, 5.5];

  state.roadEdgeX = List.generate(2, (_) => List.generate(n, (i) => i * 3.0));
  state.roadEdgeY = List.generate(2, (ei) =>
    List.generate(n, (i) => offsets[ei] + sin(i * 0.05) * 1.5));
  // Z in device frame (z-down): ~calibHeight = road surface below camera
  state.roadEdgeZ = List.generate(2, (_) =>
    List.generate(n, (i) => 1.22 - 0.02 * i));
  state.roadEdgeStds = [0.3, 0.3];
}
