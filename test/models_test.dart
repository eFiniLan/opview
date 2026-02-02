import 'package:flutter_test/flutter_test.dart';
import 'package:scope/data/models.dart';

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

  group('CerealMessage', () {
    test('fromJson with all fields', () {
      final msg = CerealMessage.fromJson({
        'type': 'carState',
        'data': {'vEgo': 10.0},
      });
      expect(msg.type, 'carState');
      expect((msg.data as Map)['vEgo'], 10.0);
    });

    test('fromJson with missing type defaults to empty string', () {
      final msg = CerealMessage.fromJson({'data': {}});
      expect(msg.type, '');
    });

    test('fromJson with null data', () {
      final msg = CerealMessage.fromJson({'type': 'test'});
      expect(msg.data, isNull);
    });

    test('fromJson with nested data', () {
      final msg = CerealMessage.fromJson({
        'type': 'modelV2',
        'data': {
          'position': {'x': [1.0, 2.0], 'y': [3.0, 4.0], 'z': [5.0, 6.0]},
          'laneLines': [],
        },
      });
      expect((msg.data as Map)['position']['x'], [1.0, 2.0]);
    });

    test('fromJson ignores extra fields', () {
      final msg = CerealMessage.fromJson({
        'type': 'carState',
        'logMonoTime': 1234567890,
        'valid': true,
        'data': {'vEgo': 5.0},
      });
      expect(msg.type, 'carState');
      expect((msg.data as Map)['vEgo'], 5.0);
    });
  });

  group('DiscoveredDevice', () {
    test('toString format', () {
      const device = DiscoveredDevice(
        displayName: 'comma 3X',
        host: '192.168.1.100',
        port: 22,
      );
      expect(device.toString(), 'comma 3X (192.168.1.100)');
    });

    test('fields accessible', () {
      const device = DiscoveredDevice(
        displayName: 'test',
        host: '10.0.0.1',
        port: 5001,
      );
      expect(device.displayName, 'test');
      expect(device.host, '10.0.0.1');
      expect(device.port, 5001);
    });
  });
}
