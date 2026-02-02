// augmented road view — the main onroad screen
// ported from openpilot selfdrive/ui/onroad/augmented_road_view.py
// + dashy augmented_road_view.js for video-scale-aware calibration
//
// layer stack (matches stock render order):
//   0. RTCVideoView (BoxFit.cover)
//   1. ClipRect -> ModelRenderer + HudRenderer + AlertRenderer
//   2. EngagementBorder (on top of everything)

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:scope/common/transformations.dart';
import 'package:scope/selfdrive/ui/ui_state.dart';
import 'package:scope/selfdrive/ui/onroad/model_renderer.dart';
import 'package:scope/selfdrive/ui/onroad/hud_renderer.dart';
import 'package:scope/selfdrive/ui/onroad/alert_renderer.dart';

// -- border colors (augmented_road_view.py:23-27) --

const borderColors = {
  UIStatus.disengaged: Color(0xFF122839),
  UIStatus.override_: Color(0xFF89928D),
  UIStatus.engaged: Color(0xFF167F40),
};

class AugmentedRoadView extends StatefulWidget {
  final UIState uiState;
  final RTCVideoRenderer? videoRenderer;

  const AugmentedRoadView({
    super.key,
    required this.uiState,
    this.videoRenderer,
  });

  @override
  State<AugmentedRoadView> createState() => _AugmentedRoadViewState();
}

class _AugmentedRoadViewState extends State<AugmentedRoadView>
    with SingleTickerProviderStateMixin {
  // cached transform inputs — only recompute when these change
  List<double> _cachedRpyCalib = [];
  List<double> _cachedWideFromDeviceEuler = [];
  String _cachedCalStatus = '';
  String _cachedDeviceType = '';
  String _cachedSensor = '';
  String _cachedStreamType = '';
  double _cachedScreenW = 0;
  double _cachedScreenH = 0;
  List<List<double>> _cachedTransform = [
    [0, 0, 0], [0, 0, 0], [0, 0, 0],
  ];

  // camera switch fade animation
  late final AnimationController _fadeController;
  bool _wasSwitchingStream = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // camera switch fade: fade out video+model, keep HUD/border visible
    final isSwitching = widget.uiState.isSwitchingStream;
    if (isSwitching && !_wasSwitchingStream) {
      _fadeController.animateTo(0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (!isSwitching && _wasSwitchingStream) {
      _fadeController.animateTo(1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    }
    _wasSwitchingStream = isSwitching;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;
        final scale = screenH / 1080.0;
        final borderSize = uiBorderSize * scale;

        // recompute transform only when inputs change
        final transform = _getTransform(screenW, screenH);

        // content rect (inside border)
        final contentRect = Rect.fromLTWH(
          borderSize, borderSize,
          screenW - 2 * borderSize, screenH - 2 * borderSize,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // layer 0 + 1a: video + model — faded during camera switch
            FadeTransition(
              opacity: _fadeController,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _videoLayer(),
                  ClipRect(
                    clipper: _ContentClipper(contentRect),
                    child: CustomPaint(
                      size: Size(screenW, screenH),
                      painter: ModelRendererPainter(
                        state: widget.uiState,
                        carSpaceTransform: transform,
                        contentRect: contentRect,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // layer 1b: HUD + alerts — always visible
            // RepaintBoundary isolates widget rebuilds from the video/model layer
            Padding(
              padding: EdgeInsets.all(borderSize),
              child: RepaintBoundary(
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HudRenderer(uiState: widget.uiState, scale: scale),
                      AlertRenderer(uiState: widget.uiState, scale: scale),
                    ],
                  ),
                ),
              ),
            ),

            // layer 2: engagement border — always visible
            CustomPaint(
              size: Size(screenW, screenH),
              painter: _EngagementBorderPainter(
                status: widget.uiState.status,
                borderSize: borderSize,
              ),
            ),

            // layer 3: "Connecting..." overlay when disconnected
            if (!widget.uiState.isConnected)
              Container(
                color: const Color(0xCC000000),
                alignment: Alignment.center,
                child: Text(
                  'Connecting…',
                  style: TextStyle(
                    color: const Color(0x99FFFFFF),
                    fontSize: 40 * scale,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }

  /// video layer: RTCVideoView with BoxFit.cover, or black placeholder
  Widget _videoLayer() {
    if (widget.videoRenderer == null) {
      return Container(color: Colors.black);
    }
    return RTCVideoView(
      widget.videoRenderer!,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  /// return cached transform, recompute only when inputs changed
  List<List<double>> _getTransform(double screenW, double screenH) {
    final st = widget.uiState;
    if (screenW == _cachedScreenW &&
        screenH == _cachedScreenH &&
        st.calStatus == _cachedCalStatus &&
        st.deviceType == _cachedDeviceType &&
        st.sensor == _cachedSensor &&
        st.streamType == _cachedStreamType &&
        listEquals(st.rpyCalib, _cachedRpyCalib) &&
        listEquals(st.wideFromDeviceEuler, _cachedWideFromDeviceEuler)) {
      return _cachedTransform;
    }

    _cachedScreenW = screenW;
    _cachedScreenH = screenH;
    _cachedCalStatus = st.calStatus;
    _cachedDeviceType = st.deviceType;
    _cachedSensor = st.sensor;
    _cachedStreamType = st.streamType;
    _cachedRpyCalib = List.of(st.rpyCalib);
    _cachedWideFromDeviceEuler = List.of(st.wideFromDeviceEuler);
    _cachedTransform = _calcFrameMatrix(screenW, screenH);
    return _cachedTransform;
  }

  /// compute the 3D->2D projection matrix
  /// ported from augmented_road_view.py:161-218 + dashy augmented_road_view.js
  List<List<double>> _calcFrameMatrix(double screenW, double screenH) {
    final isWideCamera = widget.uiState.streamType == 'wideRoad';

    // camera config — ecam for wide, fcam for road (augmented_road_view.py:174-175)
    final deviceCamera = _lookupCamera();
    final camConfig = isWideCamera ? deviceCamera.ecam : deviceCamera.fcam;
    final intrinsic = camConfig.intrinsics;
    final camW = camConfig.width.toDouble();
    final camH = camConfig.height.toDouble();

    // zoom: 2.0 for wide, 1.1 for road (augmented_road_view.py:177)
    final zoom = isWideCamera ? 2.0 : 1.1;

    // calibration: wide uses view_from_wide_calib, road uses view_from_calib (augmented_road_view.py:176)
    final calibration = isWideCamera ? _computeWideViewFromCalib() : _computeViewFromCalib();

    // video scale matches BoxFit.cover: use the larger ratio
    final videoScale = max(screenW / camW, screenH / camH);
    final focalScaled = intrinsic[0][0] * videoScale * zoom;

    // scaled intrinsic: positive focal for Flutter Canvas (Y-down)
    // stock openpilot uses -focal for OpenGL (Y-up), dashy uses -focal + canvas transform
    final scaledIntrinsic = [
      [focalScaled, 0.0, screenW / 2],
      [0.0, focalScaled, screenH / 2],
      [0.0, 0.0, 1.0],
    ];

    // final transform: scaledIntrinsic @ calibration
    return matmul3x3(scaledIntrinsic, calibration);
  }

  /// look up camera by device type + sensor, fallback to default
  DeviceCameraConfig _lookupCamera() {
    final st = widget.uiState;
    if (st.deviceType.isNotEmpty && st.sensor.isNotEmpty) {
      return deviceCameras[(st.deviceType, st.sensor)] ?? defaultDeviceCamera;
    }
    return defaultDeviceCamera;
  }

  /// road camera: view_from_calib = VIEW_FRAME_FROM_DEVICE_FRAME @ device_from_calib
  List<List<double>> _computeViewFromCalib() {
    final st = widget.uiState;
    if (st.rpyCalib.length != 3 || st.calStatus != 'calibrated') {
      return viewFrameFromDeviceFrame;
    }
    final deviceFromCalib = rotFromEuler(st.rpyCalib);
    return matmul3x3(viewFrameFromDeviceFrame, deviceFromCalib);
  }

  /// wide camera: view_from_wide_calib = VIEW_FRAME_FROM_DEVICE_FRAME @ wide_from_device @ device_from_calib
  /// (augmented_road_view.py:157-159)
  List<List<double>> _computeWideViewFromCalib() {
    final st = widget.uiState;
    if (st.rpyCalib.length != 3 || st.calStatus != 'calibrated') {
      return viewFrameFromDeviceFrame;
    }
    final deviceFromCalib = rotFromEuler(st.rpyCalib);
    if (st.wideFromDeviceEuler.length == 3) {
      final wideFromDevice = rotFromEuler(st.wideFromDeviceEuler);
      return matmul3x3(viewFrameFromDeviceFrame, matmul3x3(wideFromDevice, deviceFromCalib));
    }
    // fallback: same as road calibration
    return matmul3x3(viewFrameFromDeviceFrame, deviceFromCalib);
  }
}

// -- content area clipper (replaces scissor mode from stock) --

class _ContentClipper extends CustomClipper<Rect> {
  final Rect contentRect;
  _ContentClipper(this.contentRect);

  @override
  Rect getClip(Size size) => contentRect;

  @override
  bool shouldReclip(_ContentClipper oldClipper) => oldClipper.contentRect != contentRect;
}

// -- engagement border painter --

class _EngagementBorderPainter extends CustomPainter {
  final UIStatus status;
  final double borderSize;

  _EngagementBorderPainter({required this.status, required this.borderSize});

  @override
  void paint(Canvas canvas, Size size) {
    // outer black border
    final outerRect = Offset.zero & size;
    canvas.drawRect(outerRect, Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderSize);

    // inner colored rounded rect
    final innerRect = Rect.fromLTWH(
      borderSize / 2, borderSize / 2,
      size.width - borderSize, size.height - borderSize,
    );
    final borderColor = borderColors[status] ?? borderColors[UIStatus.disengaged]!;
    final rrect = RRect.fromRectAndRadius(innerRect, Radius.circular(borderSize * 1.2));
    canvas.drawRRect(rrect, Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderSize);
  }

  @override
  bool shouldRepaint(_EngagementBorderPainter old) =>
    old.status != status || old.borderSize != borderSize;
}
