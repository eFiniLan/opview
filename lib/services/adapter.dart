// Adapter layer abstraction
// Parses incoming data and applies to state

import 'package:scope/selfdrive/ui/ui_state.dart';

/// Abstract telemetry adapter interface
abstract class TelemetryAdapter {
  /// Parse raw message and apply to state
  /// Returns true if state was updated (should notify)
  bool apply(UIState state, String rawMessage);

  /// Reset any internal parser state
  void reset();
}
