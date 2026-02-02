// HUD renderer — speed display + MAX cruise box
// ported from openpilot selfdrive/ui/onroad/hud_renderer.py
//
// all layout at 1080p reference, scaled by screenHeight/1080.
// one widget, two draw sections: set speed box + current speed.

import 'package:flutter/material.dart';
import 'package:scope/selfdrive/ui/ui_state.dart';

// -- constants (hud_renderer.py) --

const _headerHeight = 300.0;
const _setSpeedWidthMetric = 200.0;
const _setSpeedWidthImperial = 172.0;
const _setSpeedHeight = 204.0;
const _fontCurrentSpeed = 176.0;
const _fontSpeedUnit = 66.0;
const _fontMaxSpeed = 40.0;
const _fontSetSpeed = 90.0;

// -- colors (hud_renderer.py:37-51) --

class HudColors {
  static const white = Color(0xFFFFFFFF);
  static const disengaged = Color(0xFF919B95);
  static const override_ = Color(0xFF919B95);
  static const engaged = Color(0xFF80D8A6);
  static const grey = Color(0xFFA6A6A6);
  static const darkGrey = Color(0xFF727272);
  static const blackTranslucent = Color(0xA6000000);
  static const whiteTranslucent = Color(0xC8FFFFFF);
  static const borderTranslucent = Color(0x4BFFFFFF);
  static const headerGradientStart = Color(0x72000000);
  static const headerGradientEnd = Color(0x00000000);
}

class HudRenderer extends StatelessWidget {
  final UIState uiState;
  final double scale;

  const HudRenderer({super.key, required this.uiState, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _headerGradient(),
        if (uiState.isCruiseAvailable) _setSpeedBox(),
        _currentSpeed(),
      ],
    );
  }

  /// top gradient bar: black → transparent
  Widget _headerGradient() {
    return Positioned(
      top: 0, left: 0, right: 0,
      height: _headerHeight * scale,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [HudColors.headerGradientStart, HudColors.headerGradientEnd],
          ),
        ),
      ),
    );
  }

  /// MAX speed box: rounded rect with border, "MAX" + speed value
  Widget _setSpeedBox() {
    final setSpeedWidth = uiState.isMetric ? _setSpeedWidthMetric : _setSpeedWidthImperial;
    final xOffset = 60.0 * scale + (_setSpeedWidthImperial - setSpeedWidth) / 2 * scale;

    // colors depend on engagement status
    Color maxColor = HudColors.grey;
    Color speedColor = HudColors.darkGrey;
    if (uiState.isCruiseSet) {
      speedColor = HudColors.white;
      switch (uiState.status) {
        case UIStatus.engaged: maxColor = HudColors.engaged;
        case UIStatus.disengaged: maxColor = HudColors.disengaged;
        case UIStatus.override_: maxColor = HudColors.override_;
      }
    }

    final speedText = uiState.isCruiseSet ? '${uiState.setSpeed.round()}' : '\u2013';

    return Positioned(
      left: xOffset,
      top: 45 * scale,
      child: Container(
        width: setSpeedWidth * scale,
        height: _setSpeedHeight * scale,
        decoration: BoxDecoration(
          color: HudColors.blackTranslucent,
          borderRadius: BorderRadius.circular(0.35 * _setSpeedHeight * scale / 2),
          border: Border.all(color: HudColors.borderTranslucent, width: 6 * scale),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('MAX',
              style: TextStyle(
                color: maxColor,
                fontSize: _fontMaxSpeed * scale,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            Text(speedText,
              style: TextStyle(
                color: speedColor,
                fontSize: _fontSetSpeed * scale,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// current speed: big bold number, centered
  Widget _currentSpeed() {
    final speedText = '${uiState.displaySpeed.round()}';
    final unitText = uiState.isMetric ? 'km/h' : 'mph';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: _headerHeight * scale,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(speedText,
            style: TextStyle(
              color: HudColors.white,
              fontSize: _fontCurrentSpeed * scale,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
          Text(unitText,
            style: TextStyle(
              color: HudColors.whiteTranslucent,
              fontSize: _fontSpeedUnit * scale,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
