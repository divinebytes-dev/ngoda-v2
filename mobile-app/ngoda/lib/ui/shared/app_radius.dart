import 'package:flutter/material.dart';
import 'package:ngoda/services/screen_scaling_service.dart';

class AppRadius {
  final BuildContext context;

  const AppRadius(this.context);

  double _scale(double value) {
    return ScreenScalingService.scaleSize(context, value);
  }

  // ---------------------------------------------------------------------------
  // General radius scale
  // ---------------------------------------------------------------------------

  double get sm => _scale(6);

  double get md => _scale(10);

  double get lg => _scale(16);

  double get xl => _scale(24);

  // ---------------------------------------------------------------------------
  // Semantic radius
  //
  // These intentionally remain independent from the general radius scale.
  // Their values may currently match a general token but can evolve
  // independently as the design system changes.
  // ---------------------------------------------------------------------------

  double get borderRadius => _scale(10);

  double get edgeInsert => _scale(16);

  double get cardRadius => _scale(12);

  double get dialogRadius => _scale(16);

  double get bottomSheetRadius => _scale(20);
}
