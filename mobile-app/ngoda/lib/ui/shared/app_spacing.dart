import 'package:flutter/material.dart';
import 'package:ngoda/services/screen_scaling_service.dart';

class AppSpacing {
  final BuildContext context;

  const AppSpacing(this.context);

  double _scale(double value) {
    return ScreenScalingService.scaleSize(context, value);
  }

  // ---------------------------------------------------------------------------
  // General spacing scale
  // ---------------------------------------------------------------------------

  double get xs => _scale(4);

  double get sm => _scale(8);

  double get md => _scale(16);

  double get lg => _scale(24);

  double get xl => _scale(32);

  double get xxl => _scale(40);

  double get xxxl => _scale(48);

  double get xxxxl => _scale(64);

  // ---------------------------------------------------------------------------
  // Semantic layout spacing
  //
  // These intentionally remain independent from the general spacing scale.
  // Even where values currently match, they can be adjusted later without
  // changing unrelated spacing throughout the application.
  // ---------------------------------------------------------------------------

  double get padding => _scale(16);

  double get margin => _scale(16);

  // ---------------------------------------------------------------------------
  // Component dimensions
  // ---------------------------------------------------------------------------

  double get textButtonHeight => _scale(20);

  double get buttonHeight => _scale(48);

  double get buttonWidth => _scale(140);

  double get quickActionWidth => _scale(108);

  double get quickActionHeight => _scale(65);
}
