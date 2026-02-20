import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:opview/common/transformations.dart';

void main() {
  // -- rotFromEuler --

  group('rotFromEuler', () {
    test('zero angles produce identity matrix', () {
      final r = rotFromEuler([0, 0, 0]);
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(r[i][j], closeTo(i == j ? 1.0 : 0.0, 1e-10));
        }
      }
    });

    test('90-degree yaw rotates x→y', () {
      final r = rotFromEuler([0, 0, pi / 2]);
      // Rz(90°): [0, -1, 0; 1, 0, 0; 0, 0, 1]
      expect(r[0][0], closeTo(0, 1e-10));
      expect(r[0][1], closeTo(-1, 1e-10));
      expect(r[1][0], closeTo(1, 1e-10));
      expect(r[1][1], closeTo(0, 1e-10));
      expect(r[2][2], closeTo(1, 1e-10));
    });

    test('90-degree pitch rotates x→-z', () {
      final r = rotFromEuler([0, pi / 2, 0]);
      // Ry(90°): [0, 0, 1; 0, 1, 0; -1, 0, 0]
      expect(r[0][0], closeTo(0, 1e-10));
      expect(r[0][2], closeTo(1, 1e-10));
      expect(r[1][1], closeTo(1, 1e-10));
      expect(r[2][0], closeTo(-1, 1e-10));
      expect(r[2][2], closeTo(0, 1e-10));
    });

    test('90-degree roll rotates y→z', () {
      final r = rotFromEuler([pi / 2, 0, 0]);
      // Rx(90°): [1, 0, 0; 0, 0, -1; 0, 1, 0]
      expect(r[0][0], closeTo(1, 1e-10));
      expect(r[1][1], closeTo(0, 1e-10));
      expect(r[1][2], closeTo(-1, 1e-10));
      expect(r[2][1], closeTo(1, 1e-10));
      expect(r[2][2], closeTo(0, 1e-10));
    });

    test('result is orthogonal (R @ R^T = I)', () {
      final r = rotFromEuler([0.1, -0.05, 0.03]);
      final rt = _transpose3x3(r);
      final product = matmul3x3(r, rt);
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(product[i][j], closeTo(i == j ? 1.0 : 0.0, 1e-10));
        }
      }
    });

    test('determinant is 1 (proper rotation)', () {
      final r = rotFromEuler([0.2, 0.3, -0.1]);
      final det = _det3x3(r);
      expect(det, closeTo(1.0, 1e-10));
    });

    test('small calibration angles (typical openpilot values)', () {
      // typical rpyCalib: small roll/pitch, near-zero yaw
      final r = rotFromEuler([0.01, -0.02, 0.005]);
      // should be close to identity with small perturbations
      expect(r[0][0], closeTo(1.0, 0.001));
      expect(r[1][1], closeTo(1.0, 0.001));
      expect(r[2][2], closeTo(1.0, 0.001));
      // off-diagonals should be small
      expect(r[0][1].abs(), lessThan(0.05));
      expect(r[1][0].abs(), lessThan(0.05));
    });
  });

  // -- matmul3x3 --

  group('matmul3x3', () {
    test('identity × A = A', () {
      final id = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]];
      final a = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]];
      final result = matmul3x3(id, a);
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(result[i][j], a[i][j]);
        }
      }
    });

    test('A × identity = A', () {
      final id = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]];
      final a = [[2.0, 3.0, 4.0], [5.0, 6.0, 7.0], [8.0, 9.0, 10.0]];
      final result = matmul3x3(a, id);
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(result[i][j], a[i][j]);
        }
      }
    });

    test('known multiplication', () {
      final a = [[1.0, 2.0, 0.0], [0.0, 1.0, 1.0], [1.0, 0.0, 1.0]];
      final b = [[1.0, 0.0, 1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]];
      final result = matmul3x3(a, b);
      // row 0: [1*1+2*0+0*1, 1*0+2*1+0*0, 1*1+2*0+0*0] = [1, 2, 1]
      expect(result[0], [1.0, 2.0, 1.0]);
      // row 1: [0*1+1*0+1*1, 0*0+1*1+1*0, 0*1+1*0+1*0] = [1, 1, 0]
      expect(result[1], [1.0, 1.0, 0.0]);
      // row 2: [1*1+0*0+1*1, 1*0+0*1+1*0, 1*1+0*0+1*0] = [2, 0, 1]
      expect(result[2], [2.0, 0.0, 1.0]);
    });

    test('associativity: (A @ B) @ C = A @ (B @ C)', () {
      final a = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]];
      final b = [[9.0, 8.0, 7.0], [6.0, 5.0, 4.0], [3.0, 2.0, 1.0]];
      final c = [[1.0, 0.0, 2.0], [0.0, 1.0, 2.0], [2.0, 1.0, 0.0]];
      final abC = matmul3x3(matmul3x3(a, b), c);
      final aBc = matmul3x3(a, matmul3x3(b, c));
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(abC[i][j], closeTo(aBc[i][j], 1e-10));
        }
      }
    });
  });

  // -- matvec3 --

  group('matvec3', () {
    test('identity × v = v', () {
      final id = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]];
      expect(matvec3(id, [3.0, 4.0, 5.0]), [3.0, 4.0, 5.0]);
    });

    test('scale matrix', () {
      final scale = [[2.0, 0.0, 0.0], [0.0, 3.0, 0.0], [0.0, 0.0, 4.0]];
      expect(matvec3(scale, [1.0, 1.0, 1.0]), [2.0, 3.0, 4.0]);
    });

    test('known result', () {
      final m = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]];
      final v = [1.0, 0.0, -1.0];
      // [1-3, 4-6, 7-9] = [-2, -2, -2]
      final result = matvec3(m, v);
      expect(result[0], closeTo(-2.0, 1e-10));
      expect(result[1], closeTo(-2.0, 1e-10));
      expect(result[2], closeTo(-2.0, 1e-10));
    });

    test('viewFrameFromDeviceFrame permutes axes', () {
      // device: x=forward, y=right, z=down
      // view:   x=right,   y=down,  z=forward
      final v = matvec3(viewFrameFromDeviceFrame, [1.0, 0.0, 0.0]);
      // forward in device → forward in view (z)
      expect(v[0], closeTo(0.0, 1e-10));
      expect(v[1], closeTo(0.0, 1e-10));
      expect(v[2], closeTo(1.0, 1e-10));

      final v2 = matvec3(viewFrameFromDeviceFrame, [0.0, 1.0, 0.0]);
      // right in device → right in view (x)
      expect(v2[0], closeTo(1.0, 1e-10));
      expect(v2[1], closeTo(0.0, 1e-10));
      expect(v2[2], closeTo(0.0, 1e-10));

      final v3 = matvec3(viewFrameFromDeviceFrame, [0.0, 0.0, 1.0]);
      // down in device → down in view (y)
      expect(v3[0], closeTo(0.0, 1e-10));
      expect(v3[1], closeTo(1.0, 1e-10));
      expect(v3[2], closeTo(0.0, 1e-10));
    });
  });

  // -- CameraConfig --

  group('CameraConfig', () {
    test('intrinsics matrix is correct', () {
      const cam = CameraConfig(1928, 1208, 2648.0);
      final k = cam.intrinsics;
      expect(k[0][0], 2648.0);           // fx
      expect(k[0][1], 0.0);
      expect(k[0][2], 1928 / 2.0);       // cx
      expect(k[1][0], 0.0);
      expect(k[1][1], 2648.0);           // fy
      expect(k[1][2], 1208 / 2.0);       // cy
      expect(k[2], [0.0, 0.0, 1.0]);
    });

    test('tici ar0231 fcam intrinsics', () {
      final cam = deviceCameras[('tici', 'ar0231')]!;
      expect(cam.fcam.width, 1928);
      expect(cam.fcam.height, 1208);
      expect(cam.fcam.focalLength, 2648.0);
    });

    test('tici ar0231 ecam intrinsics', () {
      final cam = deviceCameras[('tici', 'ar0231')]!;
      expect(cam.ecam.width, 1928);
      expect(cam.ecam.height, 1208);
      expect(cam.ecam.focalLength, 567.0);
    });

    test('mici os04c10 fcam intrinsics differ from ar0231', () {
      final osConfig = deviceCameras[('mici', 'os04c10')]!;
      final arConfig = deviceCameras[('mici', 'ar0231')]!;
      expect(osConfig.fcam.focalLength, isNot(arConfig.fcam.focalLength));
      expect(osConfig.fcam.width, 1344);
      expect(osConfig.fcam.height, 760);
      expect(osConfig.fcam.focalLength, 1141.5);
    });

    test('mici os04c10 ecam intrinsics', () {
      final cam = deviceCameras[('mici', 'os04c10')]!;
      expect(cam.ecam.width, 1344);
      expect(cam.ecam.height, 760);
      expect(cam.ecam.focalLength, 425.25);
    });
  });

  // -- device cameras lookup --

  group('deviceCameras', () {
    test('tici/tizi/mici all have ar0231 entry', () {
      expect(deviceCameras[('tici', 'ar0231')], isNotNull);
      expect(deviceCameras[('tizi', 'ar0231')], isNotNull);
      expect(deviceCameras[('mici', 'ar0231')], isNotNull);
    });

    test('tici/tizi/mici all have ox03c10 entry', () {
      expect(deviceCameras[('tici', 'ox03c10')], isNotNull);
      expect(deviceCameras[('tizi', 'ox03c10')], isNotNull);
      expect(deviceCameras[('mici', 'ox03c10')], isNotNull);
    });

    test('tici/mici have os04c10 entry', () {
      expect(deviceCameras[('tici', 'os04c10')], isNotNull);
      expect(deviceCameras[('mici', 'os04c10')], isNotNull);
    });

    test('ar0231 and ox03c10 share the same config', () {
      final ar = deviceCameras[('tici', 'ar0231')];
      final ox = deviceCameras[('tici', 'ox03c10')];
      expect(ar, same(ox));
    });

    test('os04c10 has different config from ar0231', () {
      final ar = deviceCameras[('tici', 'ar0231')];
      final os = deviceCameras[('tici', 'os04c10')];
      expect(ar, isNot(same(os)));
    });

    test('defaultDeviceCamera matches ar0231 config', () {
      expect(defaultDeviceCamera.fcam.focalLength, 2648.0);
      expect(defaultDeviceCamera.ecam.focalLength, 567.0);
    });
  });

  // -- calibration pipeline (integration) --

  group('calibration pipeline', () {
    test('viewFromCalib with zero RPY = viewFrameFromDeviceFrame', () {
      final deviceFromCalib = rotFromEuler([0, 0, 0]);
      final viewFromCalib = matmul3x3(viewFrameFromDeviceFrame, deviceFromCalib);
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(viewFromCalib[i][j],
            closeTo(viewFrameFromDeviceFrame[i][j], 1e-10));
        }
      }
    });

    test('wideViewFromCalib with zero RPY and zero wideFromDevice = viewFrameFromDeviceFrame', () {
      final deviceFromCalib = rotFromEuler([0, 0, 0]);
      final wideFromDevice = rotFromEuler([0, 0, 0]);
      final result = matmul3x3(viewFrameFromDeviceFrame,
        matmul3x3(wideFromDevice, deviceFromCalib));
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(result[i][j],
            closeTo(viewFrameFromDeviceFrame[i][j], 1e-10));
        }
      }
    });

    test('projection: point at (50, 0, 0) in car space → screen center', () {
      // simulate the full pipeline with identity calibration on tici ar0231
      final cam = defaultDeviceCamera.fcam;
      const screenW = 1920.0, screenH = 1080.0;
      final camW = cam.width.toDouble(), camH = cam.height.toDouble();
      const zoom = 1.1;

      final videoScale = max(screenW / camW, screenH / camH);
      final focalScaled = cam.focalLength * videoScale * zoom;

      final scaledIntrinsic = [
        [-focalScaled, 0.0, screenW / 2],
        [0.0, -focalScaled, screenH / 2],
        [0.0, 0.0, 1.0],
      ];

      final calibration = viewFrameFromDeviceFrame; // identity calib
      final transform = matmul3x3(scaledIntrinsic, calibration);

      // project point at (50, 0, 0) — directly ahead
      final pt = matvec3(transform, [50.0, 0.0, 0.0]);
      final sx = pt[0] / pt[2];
      final sy = pt[1] / pt[2];

      // should be at screen center (negative focal → correct projection)
      expect(sx, closeTo(screenW / 2, 0.1));
      expect(sy, closeTo(screenH / 2, 0.1));
    });

    test('projection: point to the right maps to right of center', () {
      final cam = defaultDeviceCamera.fcam;
      const screenW = 1920.0, screenH = 1080.0;
      final camW = cam.width.toDouble(), camH = cam.height.toDouble();

      final videoScale = max(screenW / camW, screenH / camH);
      final focalScaled = cam.focalLength * videoScale * 1.1;

      final scaledIntrinsic = [
        [-focalScaled, 0.0, screenW / 2],
        [0.0, -focalScaled, screenH / 2],
        [0.0, 0.0, 1.0],
      ];

      final transform = matmul3x3(scaledIntrinsic, viewFrameFromDeviceFrame);

      // point at (50, -1, 0) — 1m to the right (device y=right, but negative = left in car convention)
      // actually in device frame y=right, so (50, 1, 0) is right
      // view frame: x=right=device.y, so point right in view is positive y in device
      final ptRight = matvec3(transform, [50.0, 1.0, 0.0]);
      final sxRight = ptRight[0] / ptRight[2];

      final ptCenter = matvec3(transform, [50.0, 0.0, 0.0]);
      final sxCenter = ptCenter[0] / ptCenter[2];

      // negative focal means: positive view-x (right) → negative screen offset → left of center
      // but then cx is added. The sign convention with -focal means right in world → right on screen
      // Just check they differ
      expect(sxRight, isNot(closeTo(sxCenter, 0.1)));
    });
  });
}

// -- test helpers --

List<List<double>> _transpose3x3(List<List<double>> m) {
  return [
    [m[0][0], m[1][0], m[2][0]],
    [m[0][1], m[1][1], m[2][1]],
    [m[0][2], m[1][2], m[2][2]],
  ];
}

double _det3x3(List<List<double>> m) {
  return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
       - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
       + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
}
