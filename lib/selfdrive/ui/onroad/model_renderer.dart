// model renderer — path, lane lines, road edges, lead indicators
// ported from openpilot selfdrive/ui/onroad/model_renderer.py
//
// CustomPainter that projects 3D model data to 2D screen space
// using the calibrated car-space transform matrix.
// no 3D engine — just matrix math and canvas paths.

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:scope/selfdrive/ui/ui_state.dart';
import 'package:scope/common/transformations.dart';

// -- constants (model_renderer.py:14-16) --

const clipMargin = 500.0;
const minDrawDistance = 10.0;
const maxDrawDistance = 100.0;

// path gradient colors (model_renderer.py:18-28)
const throttleColors = [
  Color.fromARGB(102, 13, 248, 122),
  Color.fromARGB(89, 114, 255, 92),
  Color.fromARGB(0, 114, 255, 92),
];
const noThrottleColors = [
  Color.fromARGB(102, 242, 242, 242),
  Color.fromARGB(89, 242, 242, 242),
  Color.fromARGB(0, 242, 242, 242),
];

// lead indicator colors (model_renderer.py:308-309)
const _leadGlowColor = Color.fromARGB(255, 218, 202, 37);
const _leadChevronBase = Color.fromARGB(255, 201, 34, 49);

// -- data classes --

class ModelPoints {
  /// raw 3D points: list of [x, y, z]
  List<List<double>> rawPoints;
  /// projected 2D polygon: list of Offset
  List<Offset> projectedPoints;

  ModelPoints() : rawPoints = [], projectedPoints = [];
}

class LeadVehicle {
  List<Offset> glow;
  List<Offset> chevron;
  int fillAlpha;

  LeadVehicle() : glow = [], chevron = [], fillAlpha = 0;
}

// -- the painter --

class ModelRendererPainter extends CustomPainter {
  final UIState state;
  final List<List<double>> carSpaceTransform;
  final Rect contentRect;
  final int _version;

  ModelRendererPainter({
    required this.state,
    required this.carSpaceTransform,
    required this.contentRect,
  }) : _version = state.version;

  // working data — rebuilt each paint
  late Rect _clipRegion;
  late double _pathOffsetZ;

  @override
  void paint(Canvas canvas, Size size) {
    if (state.pathX.isEmpty) return;
    if (state.rpyCalib.isEmpty) return;
    if (_isZeroTransform()) return;

    _clipRegion = contentRect.inflate(clipMargin);
    _pathOffsetZ = state.calibHeight.isNotEmpty ? state.calibHeight[0] : heightInit;

    // build raw points from state
    final path = _buildModelPoints(state.pathX, state.pathY, state.pathZ);
    final laneLines = List.generate(4, (i) =>
      _buildModelPoints(state.laneLineX[i], state.laneLineY[i], state.laneLineZ[i]));
    final roadEdges = List.generate(2, (i) =>
      _buildModelPoints(state.roadEdgeX[i], state.roadEdgeY[i], state.roadEdgeZ[i]));

    if (path.rawPoints.isEmpty) return;

    // max draw distance from path end
    final pathXArray = path.rawPoints.map((p) => p[0]).toList();
    var maxDist = pathXArray.last.clamp(minDrawDistance, maxDrawDistance);
    final maxIdx = _getPathLengthIdx(laneLines[0].rawPoints.map((p) => p[0]).toList(), maxDist);

    // project lane lines
    for (int i = 0; i < 4; i++) {
      laneLines[i].projectedPoints = _mapLineToPolygon(
        laneLines[i].rawPoints, 0.025 * state.laneLineProbs[i].clamp(0.0, 1.0), 0.0, maxIdx, maxDist,
      );
    }

    // project road edges
    for (int i = 0; i < 2; i++) {
      roadEdges[i].projectedPoints = _mapLineToPolygon(
        roadEdges[i].rawPoints, 0.025, 0.0, maxIdx, maxDist,
      );
    }

    // project path (shorten for lead vehicle)
    if (state.leadOne != null && state.leadOne!['status'] == true) {
      final leadD = (state.leadOne!['dRel'] as num).toDouble() * 2.0;
      maxDist = (leadD - min(leadD * 0.35, 10.0)).clamp(0.0, maxDist);
    }
    final pathMaxIdx = _getPathLengthIdx(pathXArray, maxDist);
    path.projectedPoints = _mapLineToPolygon(
      path.rawPoints, 0.9, _pathOffsetZ, pathMaxIdx, maxDist, allowInvert: false,
    );

    // draw everything
    _drawLaneLines(canvas, laneLines);
    _drawRoadEdges(canvas, roadEdges);
    _drawPath(canvas, path);
    _drawLeadIndicators(canvas, pathXArray, path);
  }

  // -- drawing --

  /// draw lane lines: white, alpha from probability
  void _drawLaneLines(Canvas canvas, List<ModelPoints> laneLines) {
    for (int i = 0; i < 4; i++) {
      if (laneLines[i].projectedPoints.isEmpty) continue;
      final alpha = (state.laneLineProbs[i].clamp(0.0, 0.7) * 255).round();
      _drawPolygon(canvas, laneLines[i].projectedPoints, Color.fromARGB(alpha, 255, 255, 255));
    }
  }

  /// draw road edges: red, alpha from 1-std
  void _drawRoadEdges(Canvas canvas, List<ModelPoints> roadEdges) {
    for (int i = 0; i < 2; i++) {
      if (roadEdges[i].projectedPoints.isEmpty) continue;
      final alpha = ((1.0 - state.roadEdgeStds[i]).clamp(0.0, 1.0) * 255).round();
      _drawPolygon(canvas, roadEdges[i].projectedPoints, Color.fromARGB(alpha, 255, 0, 0));
    }
  }

  /// draw path: gradient from bottom to top
  void _drawPath(Canvas canvas, ModelPoints path) {
    if (path.projectedPoints.isEmpty) return;

    if (state.experimentalMode) {
      _drawExperimentalPath(canvas, path);
      return;
    }

    final colors = state.allowThrottle ? throttleColors : noThrottleColors;
    _drawGradientPolygon(canvas, path.projectedPoints, colors, [0.0, 0.5, 1.0]);
  }

  /// experimental mode: HSL acceleration gradient
  void _drawExperimentalPath(Canvas canvas, ModelPoints path) {
    if (path.projectedPoints.length < 2) return;

    final maxLen = min(path.projectedPoints.length ~/ 2, state.accelerationX.length);
    if (maxLen < 2) {
      _drawPolygon(canvas, path.projectedPoints, const Color.fromARGB(30, 255, 255, 255));
      return;
    }

    final colors = <Color>[];
    final stops = <double>[];

    for (int i = 0; i < maxLen; i++) {
      final trackY = path.projectedPoints[i].dy;
      if (trackY < contentRect.top || trackY > contentRect.bottom) continue;

      final linGradPoint = 1.0 - (trackY - contentRect.top) / contentRect.height;
      final pathHue = (60 + state.accelerationX[i] * 35).clamp(0.0, 120.0);
      final saturation = (state.accelerationX[i].abs() * 1.5).clamp(0.0, 1.0);
      final lightness = _lerp(0.95, 0.62, saturation);
      final alpha = _lerp(0.4, 0.0, ((linGradPoint - 0.375) / 0.375).clamp(0.0, 1.0));

      colors.add(_hslaToColor(pathHue, saturation, lightness, alpha));
      stops.add(linGradPoint);
    }

    if (colors.length > 1) {
      _drawGradientPolygon(canvas, path.projectedPoints, colors, stops);
    } else {
      _drawPolygon(canvas, path.projectedPoints, const Color.fromARGB(30, 255, 255, 255));
    }
  }

  /// draw lead vehicle indicators
  void _drawLeadIndicators(Canvas canvas, List<double> pathXArray, ModelPoints path) {
    final leads = [state.leadOne, state.leadTwo];
    for (final lead in leads) {
      if (lead == null || lead['status'] != true) continue;

      final dRel = (lead['dRel'] as num).toDouble();
      final vRel = (lead['vRel'] as num).toDouble();
      final yRel = (lead['yRel'] as num).toDouble();
      final idx = _getPathLengthIdx(pathXArray, dRel);

      final z = (idx < path.rawPoints.length) ? path.rawPoints[idx][2] : 0.0;
      final point = _mapToScreen(dRel, -yRel, z + _pathOffsetZ);
      if (point == null) continue;

      final lv = _buildLeadVehicle(dRel, vRel, point);
      _drawLeadTriangles(canvas, lv);
    }
  }

  // -- projection --

  /// project a single 3D point to screen space
  Offset? _mapToScreen(double x, double y, double z) {
    final pt = matvec3(carSpaceTransform, [x, y, z]);
    if (pt[2].abs() < 1e-6) return null;

    final sx = pt[0] / pt[2];
    final sy = pt[1] / pt[2];
    if (!_clipRegion.contains(Offset(sx, sy))) return null;

    return Offset(sx, sy);
  }

  /// convert 3D line to 2D polygon (left side + right side reversed)
  /// this is the core projection: offset left/right, project, clip, concatenate
  List<Offset> _mapLineToPolygon(
    List<List<double>> line,
    double yOff,
    double zOff,
    int maxIdx,
    double maxDistance, {
    bool allowInvert = true,
  }) {
    if (line.isEmpty) return [];

    // slice to maxIdx, interpolate endpoint for smooth ending
    final points = <List<double>>[];
    final end = min(maxIdx + 1, line.length);
    for (int i = 0; i < end; i++) {
      points.add(line[i]);
    }

    // interpolate around maxIdx
    if (maxIdx > 0 && maxIdx < line.length - 1) {
      final p0 = line[maxIdx], p1 = line[maxIdx + 1];
      final x0 = p0[0], x1 = p1[0];
      if (x1 != x0) {
        final t = (maxDistance - x0) / (x1 - x0);
        points.add([
          maxDistance,
          p0[1] + t * (p1[1] - p0[1]),
          p0[2] + t * (p1[2] - p0[2]),
        ]);
      }
    }

    // filter non-negative x
    final filtered = points.where((p) => p[0] >= 0).toList();
    if (filtered.isEmpty) return [];

    // project left and right offset points
    final leftScreen = <Offset>[];
    final rightScreen = <Offset>[];

    for (final p in filtered) {
      final leftPt = matvec3(carSpaceTransform, [p[0], p[1] - yOff, p[2] + zOff]);
      final rightPt = matvec3(carSpaceTransform, [p[0], p[1] + yOff, p[2] + zOff]);

      if (leftPt[2].abs() < 1e-6 || rightPt[2].abs() < 1e-6) continue;

      final lx = leftPt[0] / leftPt[2], ly = leftPt[1] / leftPt[2];
      final rx = rightPt[0] / rightPt[2], ry = rightPt[1] / rightPt[2];

      // clip check
      if (!_clipRegion.contains(Offset(lx, ly))) continue;
      if (!_clipRegion.contains(Offset(rx, ry))) continue;

      leftScreen.add(Offset(lx, ly));
      rightScreen.add(Offset(rx, ry));
    }

    if (leftScreen.isEmpty) return [];

    // handle Y-inversion on hills: keep only monotonically decreasing Y
    if (!allowInvert && leftScreen.length > 1) {
      final kept = <int>[0];
      var minY = leftScreen[0].dy;
      for (int i = 1; i < leftScreen.length; i++) {
        if (leftScreen[i].dy <= minY) {
          minY = leftScreen[i].dy;
          kept.add(i);
        }
      }
      if (kept.isEmpty) return [];
      final filteredLeft = kept.map((i) => leftScreen[i]).toList();
      final filteredRight = kept.map((i) => rightScreen[i]).toList();
      return [...filteredLeft, ...filteredRight.reversed];
    }

    return [...leftScreen, ...rightScreen.reversed];
  }

  // -- lead vehicle geometry (model_renderer.py:234-256) --

  LeadVehicle _buildLeadVehicle(double dRel, double vRel, Offset point) {
    final lv = LeadVehicle();

    // fill alpha: closer = more opaque, closing speed increases it
    const speedBuff = 10.0, leadBuff = 40.0;
    var fillAlpha = 0.0;
    if (dRel < leadBuff) {
      fillAlpha = 255 * (1.0 - dRel / leadBuff);
      if (vRel < 0) fillAlpha += 255 * (-vRel / speedBuff);
      fillAlpha = fillAlpha.clamp(0.0, 255.0);
    }
    lv.fillAlpha = fillAlpha.round();

    // size: bigger when closer
    final sz = ((25 * 30) / (dRel / 3 + 30)).clamp(15.0, 30.0) * 2.35;
    final x = point.dx.clamp(0.0, contentRect.width - sz / 2);
    final y = min(point.dy, contentRect.height - sz * 0.6);

    final gxo = sz / 5, gyo = sz / 10;

    lv.glow = [
      Offset(x + sz * 1.35 + gxo, y + sz + gyo),
      Offset(x, y - gyo),
      Offset(x - sz * 1.35 - gxo, y + sz + gyo),
    ];
    lv.chevron = [
      Offset(x + sz * 1.25, y + sz),
      Offset(x, y),
      Offset(x - sz * 1.25, y + sz),
    ];

    return lv;
  }

  // -- canvas helpers --

  /// draw a filled polygon with solid color
  void _drawPolygon(Canvas canvas, List<Offset> points, Color color) {
    if (points.length < 3) return;
    final path = ui.Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color);
  }

  /// draw polygon with vertical gradient
  void _drawGradientPolygon(Canvas canvas, List<Offset> points, List<Color> colors, List<double> stops) {
    if (points.length < 3) return;

    final path = ui.Path()..addPolygon(points, true);

    // find bounding box for gradient
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final shader = ui.Gradient.linear(
      Offset(0, maxY),  // bottom (gradient start = 0.0)
      Offset(0, minY),  // top (gradient end = 1.0)
      colors,
      stops,
    );

    canvas.drawPath(path, Paint()..shader = shader);
  }

  /// draw lead glow + chevron triangles
  void _drawLeadTriangles(Canvas canvas, LeadVehicle lv) {
    if (lv.glow.length < 3 || lv.chevron.length < 3) return;

    // glow: yellow
    final glowPath = ui.Path()..addPolygon(lv.glow, true);
    canvas.drawPath(glowPath, Paint()..color = _leadGlowColor);

    // chevron: red with distance-based alpha
    final chevronPath = ui.Path()..addPolygon(lv.chevron, true);
    canvas.drawPath(chevronPath, Paint()..color = _leadChevronBase.withAlpha(lv.fillAlpha));
  }

  // -- utility --

  /// find the index where posX <= distance
  int _getPathLengthIdx(List<double> posX, double distance) {
    if (posX.isEmpty) return 0;
    int idx = 0;
    for (int i = 0; i < posX.length; i++) {
      if (posX[i] <= distance) idx = i;
    }
    return idx;
  }

  /// build ModelPoints from xyz lists
  ModelPoints _buildModelPoints(List<double> x, List<double> y, List<double> z) {
    final mp = ModelPoints();
    final n = min(x.length, min(y.length, z.length));
    mp.rawPoints = List.generate(n, (i) => [x[i], y[i], z[i]]);
    return mp;
  }

  /// check if transform is all zeros (not yet calibrated)
  bool _isZeroTransform() {
    for (final row in carSpaceTransform) {
      for (final v in row) {
        if (v != 0.0) return false;
      }
    }
    return true;
  }

  /// HSL+alpha to Color (model_renderer.py:412-420)
  /// h in degrees (0-360), s/l in 0-1, a in 0-1
  Color _hslaToColor(double h, double s, double l, double a) {
    return HSLColor.fromAHSL(a, h, s, l).toColor();
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(ModelRendererPainter oldDelegate) =>
    oldDelegate._version != _version || !identical(oldDelegate.carSpaceTransform, carSpaceTransform);
}
