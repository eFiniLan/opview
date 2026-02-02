import 'package:flutter_test/flutter_test.dart';
import 'package:scope/selfdrive/ui/ui_state.dart';

void main() {
  late UIState state;

  setUp(() {
    state = UIState();
  });

  tearDown(() {
    state.dispose();
  });

  // -- applyCarState --

  group('applyCarState', () {
    test('sets vEgo', () {
      state.applyCarState({'vEgo': 15.5});
      expect(state.vEgo, 15.5);
    });

    test('sets vEgoCluster', () {
      state.applyCarState({'vEgoCluster': 16.0});
      expect(state.vEgoCluster, 16.0);
      expect(state.vEgoClusterSeen, true);
    });

    test('vEgoClusterSeen stays false if vEgoCluster is 0', () {
      state.applyCarState({'vEgoCluster': 0.0});
      expect(state.vEgoClusterSeen, false);
    });

    test('sets vCruiseCluster', () {
      state.applyCarState({'vCruiseCluster': 100.0});
      expect(state.vCruiseCluster, 100.0);
    });

    test('handles null values with defaults', () {
      state.applyCarState({});
      expect(state.vEgo, 0.0);
      expect(state.vEgoCluster, 0.0);
      expect(state.vCruiseCluster, 0.0);
    });

    test('handles int values via num cast', () {
      state.applyCarState({'vEgo': 10});
      expect(state.vEgo, 10.0);
    });
  });

  // -- applySelfdriveState --

  group('applySelfdriveState', () {
    test('engaged status when enabled', () {
      state.applySelfdriveState({'enabled': true, 'state': 'enabled'});
      expect(state.status, UIStatus.engaged);
      expect(state.enabled, true);
      expect(state.started, true);
    });

    test('disengaged status when not enabled', () {
      state.applySelfdriveState({'enabled': false, 'state': 'disabled'});
      expect(state.status, UIStatus.disengaged);
    });

    test('override status for preEnabled', () {
      state.applySelfdriveState({'enabled': true, 'state': 'preEnabled'});
      expect(state.status, UIStatus.override_);
    });

    test('override status for overriding', () {
      state.applySelfdriveState({'enabled': true, 'state': 'overriding'});
      expect(state.status, UIStatus.override_);
    });

    test('sets alert fields', () {
      state.applySelfdriveState({
        'enabled': false,
        'alertText1': 'TAKE CONTROL',
        'alertText2': 'Steering required',
        'alertSize': 'mid',
        'alertStatus': 'userPrompt',
      });
      expect(state.alertText1, 'TAKE CONTROL');
      expect(state.alertText2, 'Steering required');
      expect(state.alertSize, 2);
      expect(state.alertStatus, 1);
    });

    test('sets experimentalMode', () {
      state.applySelfdriveState({'experimentalMode': true});
      expect(state.experimentalMode, true);
    });
  });

  // -- alert parsing --

  group('alert size parsing', () {
    test('string "none" → 0', () {
      state.applySelfdriveState({'alertSize': 'none'});
      expect(state.alertSize, 0);
    });

    test('string "small" → 1', () {
      state.applySelfdriveState({'alertSize': 'small'});
      expect(state.alertSize, 1);
    });

    test('string "mid" → 2', () {
      state.applySelfdriveState({'alertSize': 'mid'});
      expect(state.alertSize, 2);
    });

    test('string "full" → 3', () {
      state.applySelfdriveState({'alertSize': 'full'});
      expect(state.alertSize, 3);
    });

    test('int value passed through', () {
      state.applySelfdriveState({'alertSize': 2});
      expect(state.alertSize, 2);
    });

    test('unknown string → 0', () {
      state.applySelfdriveState({'alertSize': 'bogus'});
      expect(state.alertSize, 0);
    });

    test('null → 0', () {
      state.applySelfdriveState({'alertSize': null});
      expect(state.alertSize, 0);
    });
  });

  group('alert status parsing', () {
    test('string "normal" → 0', () {
      state.applySelfdriveState({'alertStatus': 'normal'});
      expect(state.alertStatus, 0);
    });

    test('string "userPrompt" → 1', () {
      state.applySelfdriveState({'alertStatus': 'userPrompt'});
      expect(state.alertStatus, 1);
    });

    test('string "critical" → 2', () {
      state.applySelfdriveState({'alertStatus': 'critical'});
      expect(state.alertStatus, 2);
    });

    test('int value passed through', () {
      state.applySelfdriveState({'alertStatus': 1});
      expect(state.alertStatus, 1);
    });
  });

  // -- applyControlsState --

  group('applyControlsState', () {
    test('sets vCruiseDEPRECATED', () {
      state.applyControlsState({'vCruiseDEPRECATED': 80.0});
      expect(state.vCruiseDEPRECATED, 80.0);
    });
  });

  // -- applyModelV2 --

  group('applyModelV2', () {
    test('parses path position', () {
      state.applyModelV2({
        'position': {'x': [1.0, 2.0, 3.0], 'y': [4.0, 5.0, 6.0], 'z': [7.0, 8.0, 9.0]},
      });
      expect(state.pathX, [1.0, 2.0, 3.0]);
      expect(state.pathY, [4.0, 5.0, 6.0]);
      expect(state.pathZ, [7.0, 8.0, 9.0]);
    });

    test('parses lane lines', () {
      state.applyModelV2({
        'laneLines': [
          {'x': [1.0], 'y': [2.0], 'z': [3.0]},
          {'x': [4.0], 'y': [5.0], 'z': [6.0]},
          {'x': [7.0], 'y': [8.0], 'z': [9.0]},
          {'x': [10.0], 'y': [11.0], 'z': [12.0]},
        ],
        'laneLineProbs': [0.9, 0.8, 0.7, 0.6],
      });
      expect(state.laneLineX[0], [1.0]);
      expect(state.laneLineX[3], [10.0]);
      expect(state.laneLineProbs, [0.9, 0.8, 0.7, 0.6]);
    });

    test('parses road edges', () {
      state.applyModelV2({
        'roadEdges': [
          {'x': [1.0], 'y': [2.0], 'z': [3.0]},
          {'x': [4.0], 'y': [5.0], 'z': [6.0]},
        ],
        'roadEdgeStds': [0.3, 0.5],
      });
      expect(state.roadEdgeX[0], [1.0]);
      expect(state.roadEdgeX[1], [4.0]);
      expect(state.roadEdgeStds, [0.3, 0.5]);
    });

    test('parses acceleration', () {
      state.applyModelV2({
        'acceleration': {'x': [0.5, -0.3, 1.2]},
      });
      expect(state.accelerationX, [0.5, -0.3, 1.2]);
    });

    test('handles empty/missing data gracefully', () {
      state.applyModelV2({});
      expect(state.pathX, isEmpty);
      expect(state.pathY, isEmpty);
      expect(state.pathZ, isEmpty);
      expect(state.accelerationX, isEmpty);
    });

    test('laneLineProbs padded to 4 elements', () {
      state.applyModelV2({'laneLineProbs': [0.5, 0.6]});
      expect(state.laneLineProbs.length, 4);
      expect(state.laneLineProbs[2], 0.0);
      expect(state.laneLineProbs[3], 0.0);
    });

    test('roadEdgeStds padded to 2 elements', () {
      state.applyModelV2({'roadEdgeStds': [0.5]});
      expect(state.roadEdgeStds.length, 2);
      expect(state.roadEdgeStds[1], 0.0);
    });
  });

  // -- applyLiveCalibration --

  group('applyLiveCalibration', () {
    test('sets rpyCalib', () {
      state.applyLiveCalibration({'rpyCalib': [0.01, -0.02, 0.005]});
      expect(state.rpyCalib, [0.01, -0.02, 0.005]);
    });

    test('sets wideFromDeviceEuler', () {
      state.applyLiveCalibration({'wideFromDeviceEuler': [0.1, 0.2, 0.3]});
      expect(state.wideFromDeviceEuler, [0.1, 0.2, 0.3]);
    });

    test('sets calStatus', () {
      state.applyLiveCalibration({'calStatus': 'calibrated'});
      expect(state.calStatus, 'calibrated');
    });

    test('sets calibHeight', () {
      state.applyLiveCalibration({'height': [1.25]});
      expect(state.calibHeight, [1.25]);
    });
  });

  // -- applyRadarState --

  group('applyRadarState', () {
    test('sets lead vehicles', () {
      state.applyRadarState({
        'leadOne': {'dRel': 30.0, 'vRel': -2.0, 'yRel': 0.5, 'status': true},
        'leadTwo': {'dRel': 60.0, 'vRel': 0.0, 'yRel': 0.0, 'status': false},
      });
      expect(state.leadOne, isNotNull);
      expect(state.leadOne!['dRel'], 30.0);
      expect(state.leadTwo, isNotNull);
      expect(state.leadTwo!['status'], false);
    });

    test('null leads', () {
      state.applyRadarState({});
      expect(state.leadOne, isNull);
      expect(state.leadTwo, isNull);
    });
  });

  // -- applyLongitudinalPlan --

  group('applyLongitudinalPlan', () {
    test('sets allowThrottle', () {
      state.applyLongitudinalPlan({'allowThrottle': false});
      expect(state.allowThrottle, false);
    });

    test('defaults to true', () {
      state.applyLongitudinalPlan({});
      expect(state.allowThrottle, true);
    });
  });

  // -- applyDeviceState --

  group('applyDeviceState', () {
    test('sets deviceType', () {
      state.applyDeviceState({'deviceType': 'tici'});
      expect(state.deviceType, 'tici');
    });

    test('sets started', () {
      state.applyDeviceState({'started': true});
      expect(state.started, true);
    });
  });

  // -- applyRoadCameraState --

  group('applyRoadCameraState', () {
    test('sets sensor', () {
      state.applyRoadCameraState({'sensor': 'ar0231'});
      expect(state.sensor, 'ar0231');
    });
  });

  // -- derived values --

  group('displaySpeed', () {
    test('metric: vEgo * 3.6', () {
      state.isMetric = true;
      state.applyCarState({'vEgo': 10.0}); // 36 km/h
      expect(state.displaySpeed, closeTo(36.0, 0.01));
    });

    test('imperial: vEgo * 2.23694', () {
      state.isMetric = false;
      state.applyCarState({'vEgo': 10.0}); // ~22.4 mph
      expect(state.displaySpeed, closeTo(22.3694, 0.01));
    });

    test('uses vEgoCluster when seen', () {
      state.isMetric = true;
      state.applyCarState({'vEgo': 10.0, 'vEgoCluster': 11.0});
      // vEgoCluster=11 seen → display = 11 * 3.6 = 39.6
      expect(state.displaySpeed, closeTo(39.6, 0.01));
    });

    test('uses vEgo when vEgoCluster not yet seen', () {
      state.isMetric = true;
      state.applyCarState({'vEgo': 10.0, 'vEgoCluster': 0.0});
      // vEgoCluster=0 → not seen → use vEgo = 10 * 3.6 = 36
      expect(state.displaySpeed, closeTo(36.0, 0.01));
    });

    test('negative speed clamped to 0', () {
      state.applyCarState({'vEgo': -1.0});
      expect(state.displaySpeed, 0.0);
    });
  });

  group('setSpeed / isCruiseSet', () {
    test('isCruiseSet false when vCruiseCluster is 0 and vCruiseDEPRECATED is 0', () {
      expect(state.isCruiseSet, false);
    });

    test('isCruiseSet true when vCruiseCluster is valid', () {
      state.applyCarState({'vCruiseCluster': 100.0});
      expect(state.isCruiseSet, true);
    });

    test('isCruiseSet false when speed is setSpeedNA (255)', () {
      state.applyCarState({'vCruiseCluster': 255.0});
      expect(state.isCruiseSet, false);
    });

    test('setSpeed metric: raw value', () {
      state.isMetric = true;
      state.applyCarState({'vCruiseCluster': 100.0});
      expect(state.setSpeed, closeTo(100.0, 0.01));
    });

    test('setSpeed imperial: converted', () {
      state.isMetric = false;
      state.applyCarState({'vCruiseCluster': 100.0});
      expect(state.setSpeed, closeTo(100.0 * kmToMile, 0.01));
    });

    test('vCruiseDEPRECATED used as fallback', () {
      state.applyControlsState({'vCruiseDEPRECATED': 80.0});
      expect(state.isCruiseSet, true);
      expect(state.setSpeed, closeTo(80.0, 0.01));
    });

    test('vCruiseCluster takes priority over deprecated', () {
      state.applyCarState({'vCruiseCluster': 100.0});
      state.applyControlsState({'vCruiseDEPRECATED': 80.0});
      expect(state.setSpeed, closeTo(100.0, 0.01));
    });

    test('isCruiseAvailable false when speed is -1', () {
      state.applyCarState({'vCruiseCluster': -1.0});
      expect(state.isCruiseAvailable, false);
    });

    test('isCruiseAvailable true when speed is 0', () {
      state.applyCarState({'vCruiseCluster': 0.0});
      expect(state.isCruiseAvailable, true);
    });
  });

  // -- version / dirty --

  group('version tracking', () {
    test('version starts at 0', () {
      expect(state.version, 0);
    });

    test('markDirty does not increment version immediately', () {
      state.markDirty();
      expect(state.version, 0);
    });
  });

  // -- streamType --

  group('streamType', () {
    test('defaults to road', () {
      expect(state.streamType, 'road');
    });

    test('can be set to wideRoad', () {
      state.streamType = 'wideRoad';
      expect(state.streamType, 'wideRoad');
    });
  });
}
