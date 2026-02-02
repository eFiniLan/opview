// mDNS discovery — find comma devices on the network
// ported from dashy mobile NsdDiscoveryManager.kt
//
// looks for _ssh._tcp services starting with "comma SSH".
// extracts display name from bracket notation: "comma SSH [MyDevice]" → "MyDevice"

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:scope/data/models.dart';

// bonsoir expects NO trailing dot (normalizer splits on '.' and expects exactly 2 parts)
const _serviceType = '_ssh._tcp';
const _servicePrefix = 'comma SSH';
final _bracketRegex = RegExp(r'\[(.*?)\]');

class DiscoveryService {
  BonsoirDiscovery? _discovery;
  final _devicesController = StreamController<DiscoveredDevice>.broadcast();
  Stream<DiscoveredDevice> get devices => _devicesController.stream;

  /// start discovering comma devices
  Future<void> start() async {
    try {
      _discovery = BonsoirDiscovery(type: _serviceType);
      await _discovery!.ready;

      _discovery!.eventStream?.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          // service found but not yet resolved — need to resolve for IP/port
          final service = event.service;
          if (service == null) return;
          if (!service.name.startsWith(_servicePrefix)) return;
          debugPrint('[scope] found service: ${service.name}, resolving...');
          service.resolve(_discovery!.serviceResolver);
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
          // service resolved — now we have host + port
          final service = event.service;
          if (service == null) return;
          if (!service.name.startsWith(_servicePrefix)) return;

          final resolved = service as ResolvedBonsoirService;
          final host = resolved.host;
          if (host == null || host.isEmpty) return;

          debugPrint('[scope] resolved: ${service.name} → $host:${resolved.port}');
          final device = DiscoveredDevice(
            displayName: _extractDisplayName(service.name, host),
            host: host,
            port: resolved.port,
          );
          _devicesController.add(device);
        }
      });

      await _discovery!.start();
      debugPrint('[scope] discovery started (type: $_serviceType)');
    } catch (e) {
      debugPrint('[scope] discovery failed to start: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _discovery?.stop();
    } catch (e) {
      debugPrint('[scope] discovery stop error: $e');
    }
    _discovery = null;
  }

  void dispose() {
    stop();
    _devicesController.close();
  }
}

/// extract name from brackets, or use fallback
/// "comma SSH [MyDevice]" → "MyDevice"
String _extractDisplayName(String serviceName, String fallback) {
  final match = _bracketRegex.firstMatch(serviceName);
  return match?.group(1) ?? fallback;
}
