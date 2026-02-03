// Transport layer abstraction
// Handles connection to the device

import 'dart:async';

/// Transport connection state
enum TransportState {
  disconnected,
  connecting,
  connected,
  failed,
}

/// Abstract transport interface
abstract class Transport {
  /// Stream of incoming data messages
  Stream<String> get dataStream;

  /// Stream of connection state changes
  Stream<TransportState> get stateStream;

  /// Video renderer (if supported by transport)
  /// Returns null if transport doesn't support video
  dynamic get videoRenderer;

  /// Connect to a host
  Future<void> connect(String host, {String camera = 'road'});

  /// Close current connection
  Future<void> close();

  /// Clean up resources
  Future<void> dispose();
}
