import 'package:flutter/material.dart';

class ScreenScalingService {
  /// Compact phone reference width.
  ///
  /// Smaller / older phones are protected from excessive shrinking
  /// by the minimum scale.
  static const double _compactReferenceWidth = 360.0;

  /// Modern phone reference width.
  static const double _modernReferenceWidth = 390.0;

  /// Width range over which the reference transitions smoothly
  /// from compact-phone sizing to modern-phone sizing.
  static const double _transitionStartWidth = 360.0;
  static const double _transitionEndWidth = 390.0;

  /// Prevent UI dimensions from becoming excessively small or large.
  static const double _minScale = 0.90;
  static const double _maxScale = 1.20;

  /// Optional application-level font scaling preference.
  static double _userScaleFactor = 1.0;

  static double get userScaleFactor {
    return _userScaleFactor;
  }

  static void setUserScale(double value) {
    _userScaleFactor = value.clamp(0.8, 1.2);
  }

  // ---------------------------------------------------------------------------
  // Font scaling
  // ---------------------------------------------------------------------------

  static double scaleFont(BuildContext context, double baseSize) {
    final scaledSize = baseSize * _userScaleFactor;

    return MediaQuery.textScalerOf(context).scale(scaledSize);
  }

  // ---------------------------------------------------------------------------
  // UI size scaling
  // ---------------------------------------------------------------------------

  static double scaleSize(BuildContext context, double baseSize) {
    return baseSize * _screenScaleFactor(context);
  }

  // ---------------------------------------------------------------------------
  // Screen scaling
  // ---------------------------------------------------------------------------

  static double _screenScaleFactor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    final referenceWidth = _referenceWidthFor(width);

    final scale = width / referenceWidth;

    return scale.clamp(_minScale, _maxScale);
  }

  // ---------------------------------------------------------------------------
  // Reference width
  // ---------------------------------------------------------------------------

  static double _referenceWidthFor(double width) {
    if (width <= _transitionStartWidth) {
      return _compactReferenceWidth;
    }

    if (width >= _transitionEndWidth) {
      return _modernReferenceWidth;
    }

    final progress =
        (width - _transitionStartWidth) /
        (_transitionEndWidth - _transitionStartWidth);

    return _compactReferenceWidth +
        ((_modernReferenceWidth - _compactReferenceWidth) * progress);
  }
}

// import 'package:flutter/material.dart';

// class ScreenScalingService {
//   static const double _modernBaselineWidth = 375.0;
//   static const double _legacyBaselineWidth = 400.0;

//   static const double _minScale = 0.85;
//   static const double _maxScale = 1.25;

//   static double userScaleFactor = 1.0;

//   static void setUserScale(double value) {
//     userScaleFactor = value.clamp(0.8, 1.2);
//   }

//   // ---------------------------------------------------------------------------
//   // Font scaling
//   // ---------------------------------------------------------------------------

//   static double scaleFont(BuildContext context, double baseSize) {
//     final screenScale = _screenScaleFactor(context);

//     final scaledBaseSize = baseSize * screenScale * userScaleFactor;

//     return MediaQuery.textScalerOf(context).scale(scaledBaseSize);
//   }

//   // ---------------------------------------------------------------------------
//   // UI size scaling
//   // ---------------------------------------------------------------------------

//   static double scaleSize(BuildContext context, double baseSize) {
//     return baseSize * _screenScaleFactor(context);
//   }

//   // ---------------------------------------------------------------------------
//   // Screen scale
//   // ---------------------------------------------------------------------------

//   static double _screenScaleFactor(BuildContext context) {
//     final size = MediaQuery.sizeOf(context);

//     final width = size.width;
//     final shortestSide = size.shortestSide;

//     final baselineWidth = shortestSide < 380
//         ? _legacyBaselineWidth
//         : _modernBaselineWidth;

//     final scale = width / baselineWidth;

//     return scale.clamp(_minScale, _maxScale);
//   }
// }
