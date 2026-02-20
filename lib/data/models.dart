// data models for webrtc messaging

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
