// webrtcd API client
// POST /stream to negotiate WebRTC session
// ported from openpilot system/webrtc/webrtcd.py

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:opview/data/models.dart';

// everything the stock UI subscribes to
const bridgeServicesOut = [
  'carState',
  'selfdriveState',
  'controlsState',
  'modelV2',
  'liveCalibration',
  'radarState',
  'longitudinalPlan',
  'deviceState',
  'roadCameraState',
];

/// exchange SDP with webrtcd, returns answer SDP
Future<Map<String, dynamic>> postStream(String host, String offerSdp, {String camera = 'road'}) async {
  final request = StreamRequest(
    sdp: offerSdp,
    cameras: [camera],
    bridgeServicesOut: bridgeServicesOut,
  );

  final url = Uri.parse('http://$host:5001/stream');
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(request.toJson()),
  ).timeout(const Duration(seconds: 10));

  if (response.statusCode != 200) {
    throw Exception('webrtcd returned ${response.statusCode}: ${response.body}');
  }

  return jsonDecode(response.body) as Map<String, dynamic>;
}
