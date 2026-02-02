// data models for webrtc messaging
// thin wrappers — just enough structure, no over-abstraction

/// device found via mDNS discovery
class DiscoveredDevice {
  final String displayName;
  final String host;
  final int port;

  const DiscoveredDevice({
    required this.displayName,
    required this.host,
    required this.port,
  });

  @override
  String toString() => '$displayName ($host)';
}

/// POST body for /stream endpoint
class StreamRequest {
  final String sdp;
  final List<String> cameras;
  final List<String> bridgeServicesIn;
  final List<String> bridgeServicesOut;

  const StreamRequest({
    required this.sdp,
    this.cameras = const ['road'],
    this.bridgeServicesIn = const [],
    required this.bridgeServicesOut,
  });

  Map<String, dynamic> toJson() => {
    'sdp': sdp,
    'cameras': cameras,
    'bridge_services_in': bridgeServicesIn,
    'bridge_services_out': bridgeServicesOut,
  };
}

/// parsed cereal message from data channel
class CerealMessage {
  final String type;
  final int logMonoTime;
  final bool valid;
  final dynamic data;

  const CerealMessage({
    required this.type,
    required this.logMonoTime,
    required this.valid,
    required this.data,
  });

  factory CerealMessage.fromJson(Map<String, dynamic> json) => CerealMessage(
    type: json['type'] as String? ?? '',
    logMonoTime: (json['logMonoTime'] as num?)?.toInt() ?? 0,
    valid: json['valid'] as bool? ?? true,
    data: json['data'],
  );
}
