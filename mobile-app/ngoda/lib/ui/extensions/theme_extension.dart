import 'package:flutter/material.dart';

extension ThemeX on BuildContext {
  ThemeData get theme {
    return Theme.of(this);
  }

  ColorScheme get colorScheme {
    return Theme.of(this).colorScheme;
  }

  TextTheme get textTheme {
    return Theme.of(this).textTheme;
  }

  Brightness get brightness {
    return Theme.of(this).brightness;
  }

  bool get isDarkMode {
    return brightness == Brightness.dark;
  }

  bool get isLightMode {
    return brightness == Brightness.light;
  }
}
