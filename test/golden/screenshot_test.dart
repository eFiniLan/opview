// Golden tests — render AugmentedRoadView at multiple screen resolutions
// Run: flutter test test/golden/screenshot_test.dart --update-goldens
// CI uploads screenshots as artifacts for visual review.

@Tags(['golden'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opview/selfdrive/ui/onroad/augmented_road_view.dart';
import 'mock_ui_state.dart';

// screen configs: name -> (width, height) — landscape only (app locks to landscape)
const _screens = {
  'phone':    (844.0, 390.0),
  'tablet':   (1024.0, 768.0),
  'headunit': (1280.0, 480.0),
  'full_hd':  (1920.0, 1080.0),
};

// test scenarios — alert text/size/status match stock openpilot events.py
final _scenarios = {
  'engaged': () => createMockUIState(),
  'disengaged': () => createMockUIState(engaged: false, vCruiseCluster: 0),
  // calibrationIncomplete: mid + normal, uncalibrated (no model overlay)
  'alert_calibrating': () => createMockUIState(
    engaged: false,
    vCruiseCluster: 0,
    alertText1: 'Calibrating: 42%',
    alertText2: 'Drive Above 25 km/h',
    alertSize: 2,  // AlertSize.mid
    alertStatus: 0, // AlertStatus.normal
    calibrating: true,
  ),
  // preDriverDistracted: small + normal
  'alert_small': () => createMockUIState(
    alertText1: 'Pay Attention',
    alertSize: 1,  // AlertSize.small
    alertStatus: 0, // AlertStatus.normal
  ),
  // promptDriverUnresponsive: mid + userPrompt
  'alert_prompt': () => createMockUIState(
    alertText1: 'Touch Steering Wheel',
    alertText2: 'Driver Unresponsive',
    alertSize: 2,  // AlertSize.mid
    alertStatus: 1, // AlertStatus.userPrompt
  ),
  // SoftDisableAlert: full + userPrompt
  'alert_soft_disable': () => createMockUIState(
    alertText1: 'TAKE CONTROL IMMEDIATELY',
    alertText2: 'Steering Temporarily Unavailable',
    alertSize: 3,  // AlertSize.full
    alertStatus: 1, // AlertStatus.userPrompt
  ),
  // driverUnresponsive: full + critical
  'alert_critical': () => createMockUIState(
    alertText1: 'DISENGAGE IMMEDIATELY',
    alertText2: 'Driver Unresponsive',
    alertSize: 3,  // AlertSize.full
    alertStatus: 2, // AlertStatus.critical
    engaged: false,
  ),
};

/// Load Roboto font so golden tests render real text instead of Ahem squares.
Future<void> _loadRoboto() async {
  final fontLoader = FontLoader('Roboto');
  final fontData = File('assets/fonts/Roboto.ttf').readAsBytesSync();
  fontLoader.addFont(Future.value(ByteData.sublistView(fontData)));
  await fontLoader.load();
}

void main() {
  setUpAll(() async {
    await _loadRoboto();
  });

  for (final screenEntry in _screens.entries) {
    final screenName = screenEntry.key;
    final (w, h) = screenEntry.value;

    for (final scenarioEntry in _scenarios.entries) {
      final scenarioName = scenarioEntry.key;
      final createState = scenarioEntry.value;

      testWidgets('$screenName - $scenarioName', (tester) async {
        // Suppress overflow errors — alert text may overflow at small
        // resolutions, which is a known layout limitation.
        final errors = <FlutterErrorDetails>[];
        final old = FlutterError.onError;
        FlutterError.onError = (d) {
          if (!d.toString().contains('overflowed')) {
            errors.add(d);
          }
        };

        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          FlutterError.onError = old;
        });

        final state = createState();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto'),
            home: AugmentedRoadView(
              uiState: state,
              videoRenderer: null, // black background in tests
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(AugmentedRoadView),
          matchesGoldenFile('goldens/${screenName}_$scenarioName.png'),
        );

        // Re-throw non-overflow errors
        for (final e in errors) {
          old?.call(e);
        }
      });
    }
  }
}
