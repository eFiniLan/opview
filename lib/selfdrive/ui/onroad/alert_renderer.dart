// alert renderer — severity banners
// ported from openpilot selfdrive/ui/onroad/alert_renderer.py
//
// three sizes: small (single line), mid (title + subtitle), full (big text).
// three severities: normal (dark), userPrompt (orange), critical (red).

import 'package:flutter/material.dart';
import 'package:scope/selfdrive/ui/ui_state.dart';

// -- constants (alert_renderer.py:16-28) --

const _alertMargin = 40.0;
const _alertPadding = 60.0;
const _alertBorderRadius = 30.0;
const _alertLineSpacing = 45.0;

const _alertFontSmall = 66.0;
const _alertFontMedium = 74.0;
const _alertFontBig = 88.0;

const _alertHeightSmall = 271.0;
const _alertHeightMid = 420.0;

// alert size enum values from cereal
const _sizeNone = 0;
const _sizeSmall = 1;
const _sizeFull = 3;

// status enum values from cereal
const _statusNormal = 0;
const _statusUserPrompt = 1;
const _statusCritical = 2;

// -- colors (alert_renderer.py:34-38) --

const _alertColors = {
  _statusNormal: Color(0xF1151515),
  _statusUserPrompt: Color(0xF1DA6F25),
  _statusCritical: Color(0xF1C92231),
};

class AlertRenderer extends StatelessWidget {
  final UIState uiState;
  final double scale;

  const AlertRenderer({super.key, required this.uiState, required this.scale});

  @override
  Widget build(BuildContext context) {
    if (uiState.alertSize == _sizeNone) return const SizedBox.shrink();

    final bgColor = _alertColors[uiState.alertStatus] ?? _alertColors[_statusNormal]!;
    final size = uiState.alertSize;

    if (size == _sizeFull) return _fullAlert(bgColor);

    // small or mid: positioned at bottom
    final h = (size == _sizeSmall ? _alertHeightSmall : _alertHeightMid) * scale;
    final m = _alertMargin * scale;

    return Positioned(
      left: m,
      right: m,
      bottom: m,
      height: h - 2 * m,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(_alertBorderRadius * scale),
        ),
        padding: EdgeInsets.symmetric(horizontal: _alertPadding * scale),
        child: size == _sizeSmall ? _smallContent() : _midContent(),
      ),
    );
  }

  /// single bold line, centered
  Widget _smallContent() {
    return Center(
      child: Text(uiState.alertText1,
        style: TextStyle(
          color: Colors.white,
          fontSize: _alertFontMedium * scale,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// title + subtitle
  Widget _midContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(uiState.alertText1,
          style: TextStyle(
            color: Colors.white,
            fontSize: _alertFontBig * scale,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: _alertLineSpacing * scale),
        Text(uiState.alertText2,
          style: TextStyle(
            color: Colors.white,
            fontSize: _alertFontSmall * scale,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// full screen alert
  Widget _fullAlert(Color bgColor) {
    final isLong = uiState.alertText1.length > 15;
    final fontSize1 = (isLong ? 132.0 : 177.0) * scale;

    return Positioned.fill(
      child: Container(
        color: bgColor,
        padding: EdgeInsets.all(_alertPadding * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            Text(uiState.alertText1,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize1,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            Text(uiState.alertText2,
              style: TextStyle(
                color: Colors.white,
                fontSize: _alertFontBig * scale,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
