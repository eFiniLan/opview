// mDNS discovery implementation
// Finds comma devices via _ssh._tcp service

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:scope/services/discovery.dart';

// bonsoir expects NO trailing dot
const _serviceType = '_ssh._tcp';
const _servicePrefix = 'comma SSH';
final _bracketRegex = RegExp(r'\[(.*?)\]');

class MdnsDiscovery implements Discovery {
  BonsoirDiscovery? _discovery;
  StreamSubscription? _eventSub;
  final _devicesController = StreamController<DiscoveredDevice>.broadcast();

  @override
  Stream<DiscoveredDevice> get devices => _devicesController.stream;

  @override
  Future<void> start() async {
    try {
      _discovery = BonsoirDiscovery(type: _serviceType);
      await _discovery!.ready;

      _eventSub = _discovery!.eventStream?.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          final service = event.service;
          if (service == null) return;
          if (!service.name.startsWith(_servicePrefix)) return;
          debugPrint('[scope] found service: ${service.name}, resolving...');
          service.resolve(_discovery!.serviceResolver);
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
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
            deviceId: _extractDeviceId(service.name),
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

  @override
  Future<void> stop() async {
    _eventSub?.cancel();
    _eventSub = null;
    try {
      await _discovery?.stop();
    } catch (e) {
      debugPrint('[scope] discovery stop error: $e');
    }
    _discovery = null;
  }

  @override
  void dispose() {
    stop();
    _devicesController.close();
  }
}

/// Extract name from brackets: "comma SSH - tici - [comma-xxx]" → "comma-xxx"
String _extractDisplayName(String serviceName, String fallback) {
  final match = _bracketRegex.firstMatch(serviceName);
  return match?.group(1) ?? fallback;
}

/// Extract device ID from service name
String? _extractDeviceId(String serviceName) {
  final match = _bracketRegex.firstMatch(serviceName);
  return match?.group(1);
}
