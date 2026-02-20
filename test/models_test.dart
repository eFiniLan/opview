import 'package:flutter_test/flutter_test.dart';
import 'package:opview/data/models.dart';

void main() {
  group('StreamRequest', () {
    test('toJson produces correct structure', () {
      const req = StreamRequest(
        sdp: 'v=0\r\n',
        cameras: ['road'],
        bridgeServicesOut: ['carState', 'modelV2'],
      );
      final json = req.toJson();
      expect(json['sdp'], 'v=0\r\n');
      expect(json['cameras'], ['road']);
      expect(json['bridge_services_in'], isEmpty);
      expect(json['bridge_services_out'], ['carState', 'modelV2']);
    });

    test('toJson with wideRoad camera', () {
      const req = StreamRequest(
        sdp: 'offer',
        cameras: ['wideRoad'],
        bridgeServicesOut: ['carState'],
      );
      expect(req.toJson()['cameras'], ['wideRoad']);
    });

    test('default cameras is road', () {
      const req = StreamRequest(
        sdp: 'offer',
        bridgeServicesOut: ['carState'],
      );
      expect(req.cameras, ['road']);
    });

    test('default bridgeServicesIn is empty', () {
      const req = StreamRequest(
        sdp: 'offer',
        bridgeServicesOut: ['carState'],
      );
      expect(req.bridgeServicesIn, isEmpty);
    });
  });
}
