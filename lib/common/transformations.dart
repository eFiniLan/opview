// camera intrinsics + coordinate transforms + rotation math
// ported from openpilot common/transformations/camera.py + orientation.py
//
// no numpy, no 3D library. just 3x3 matrices in lists.
// all projection is: intrinsic @ calibration @ point → perspective divide

import 'dart:math';

// -- camera config --

class CameraConfig {
  final int width;
  final int height;
  final double focalLength;

  const CameraConfig(this.width, this.height, this.focalLength);

  // intrinsic matrix K — camera_frame_from_view_frame
  List<List<double>> get intrinsics => [
    [focalLength, 0.0, width / 2.0],
    [0.0, focalLength, height / 2.0],
    [0.0, 0.0, 1.0],
  ];
}

class DeviceCameraConfig {
  final CameraConfig fcam;  // forward camera
  final CameraConfig ecam;  // external/wide camera

  const DeviceCameraConfig({required this.fcam, required this.ecam});
}

// -- hardcoded device cameras (from camera.py) --

const _arOxFisheye = CameraConfig(1928, 1208, 567.0);
const _osFisheye = CameraConfig(1344, 760, 425.25);  // 2688/2, 1520/2, 567*3/4
const _arOxConfig = DeviceCameraConfig(
  fcam: CameraConfig(1928, 1208, 2648.0),
  ecam: _arOxFisheye,
);
const _osConfig = DeviceCameraConfig(
  fcam: CameraConfig(1344, 760, 1141.5),  // 1522*3/4
  ecam: _osFisheye,
);

// lookup by (deviceType, sensor) — matches camera.py DEVICE_CAMERAS
final Map<(String, String), DeviceCameraConfig> deviceCameras = {
  // tici variants
  ('tici', 'ar0231'): _arOxConfig,
  ('tici', 'ox03c10'): _arOxConfig,
  ('tici', 'os04c10'): _osConfig,
  ('tici', 'unknown'): _arOxConfig,
  // tizi variants
  ('tizi', 'ar0231'): _arOxConfig,
  ('tizi', 'ox03c10'): _arOxConfig,
  ('tizi', 'os04c10'): _osConfig,
  // mici variants
  ('mici', 'ar0231'): _arOxConfig,
  ('mici', 'ox03c10'): _arOxConfig,
  ('mici', 'os04c10'): _osConfig,
  // fallbacks
  ('unknown', 'ar0231'): _arOxConfig,
  ('unknown', 'ox03c10'): _arOxConfig,
  ('pc', 'unknown'): _arOxConfig,
};

// default when we haven't seen deviceState yet
const defaultDeviceCamera = _arOxConfig;

// -- coordinate frame transforms --
// device: x=forward, y=right, z=down
// view:   x=right,   y=down,  z=forward

const viewFrameFromDeviceFrame = [
  [0.0, 1.0, 0.0],
  [0.0, 0.0, 1.0],
  [1.0, 0.0, 0.0],
];

// calibrationd default height
const heightInit = 1.22;

// -- matrix math --

/// 3x3 matrix multiply: C = A @ B
List<List<double>> matmul3x3(List<List<double>> a, List<List<double>> b) {
  final c = List.generate(3, (_) => List.filled(3, 0.0));
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      c[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j];
    }
  }
  return c;
}

/// 3x3 matrix @ 3-vector
List<double> matvec3(List<List<double>> m, List<double> v) {
  return [
    m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
    m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
    m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
  ];
}

// -- rotation from euler angles --

/// rotation matrix from [roll, pitch, yaw]
/// standard aerospace: Rz(yaw) @ Ry(pitch) @ Rx(roll)
List<List<double>> rotFromEuler(List<double> rpy) {
  final r = rpy[0], p = rpy[1], y = rpy[2];
  final cr = cos(r), sr = sin(r);
  final cp = cos(p), sp = sin(p);
  final cy = cos(y), sy = sin(y);

  return [
    [cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr],
    [sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr],
    [-sp,     cp * sr,                cp * cr               ],
  ];
}
