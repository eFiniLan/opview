// Discovery layer abstraction
// Finds comma devices on the network

import 'dart:async';

/// Discovered device info
class DiscoveredDevice {
  final String host;
  final String displayName;
  final String? deviceId;

  DiscoveredDevice({
    required this.host,
    required this.displayName,
    this.deviceId,
  });
}

/// Abstract discovery interface
abstract class Discovery {
  /// Stream of discovered devices
  Stream<DiscoveredDevice> get devices;

  /// Start discovery
  Future<void> start();

  /// Stop discovery
  Future<void> stop();

  /// Clean up resources
  void dispose();
}
