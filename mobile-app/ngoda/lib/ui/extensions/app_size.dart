import 'package:flutter/widgets.dart';
import 'package:ngoda/ui/shared/app_icon_size.dart';
import 'package:ngoda/ui/shared/app_radius.dart';
import 'package:ngoda/ui/shared/app_spacing.dart';

extension AppSizeX on BuildContext {
  AppSpacing get spacing {
    return AppSpacing(this);
  }

  AppRadius get radius {
    return AppRadius(this);
  }

  AppIconSize get iconSize {
    return AppIconSize(this);
  }
}
