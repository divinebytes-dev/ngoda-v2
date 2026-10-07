import 'dart:ui';

import 'package:flutter/services.dart';

// -----------------------------------------------------------------------------
// Responsive breakpoints
//
// These are layout breakpoints, not spacing values, so they intentionally
// remain here rather than being placed in AppSpacing.
// -----------------------------------------------------------------------------

const double mobileBreakpoint = 600;
const double desktopBreakpoint = 1024;

// -----------------------------------------------------------------------------
// Device dimensions
// -----------------------------------------------------------------------------

FlutterView get _primaryView {
  return PlatformDispatcher.instance.views.first;
}

double deviceWidth() {
  final view = _primaryView;

  return view.physicalSize.width / view.devicePixelRatio;
}

double deviceHeight() {
  final view = _primaryView;

  return view.physicalSize.height / view.devicePixelRatio;
}

// -----------------------------------------------------------------------------
// Responsive helpers
// -----------------------------------------------------------------------------

bool isMobilePhone() {
  return deviceWidth() < mobileBreakpoint;
}

bool isTablet() {
  final width = deviceWidth();

  return width >= mobileBreakpoint && width < desktopBreakpoint;
}

bool isDesktop() {
  return deviceWidth() >= desktopBreakpoint;
}

// -----------------------------------------------------------------------------
// Orientation
// -----------------------------------------------------------------------------

Future<void> setOrientation() async {
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
}
