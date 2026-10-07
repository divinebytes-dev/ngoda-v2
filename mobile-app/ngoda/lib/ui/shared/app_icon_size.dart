import 'package:flutter/material.dart';
import 'package:ngoda/services/screen_scaling_service.dart';

class AppIconSize {
  final BuildContext context;

  const AppIconSize(this.context);

  double _scale(double value) {
    return ScreenScalingService.scaleSize(context, value);
  }

  // ---------------------------------------------------------------------------
  // Icon size scale
  // ---------------------------------------------------------------------------

  double get small => _scale(16);

  double get medium => _scale(20);

  double get large => _scale(24);

  double get xl => _scale(32);
}
