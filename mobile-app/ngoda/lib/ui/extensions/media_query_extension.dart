import 'package:flutter/material.dart';

extension MediaQueryX on BuildContext {
  MediaQueryData get mediaQuery {
    return MediaQuery.of(this);
  }

  Size get screenSize {
    return MediaQuery.sizeOf(this);
  }

  double get screenWidth {
    return MediaQuery.sizeOf(this).width;
  }

  double get screenHeight {
    return MediaQuery.sizeOf(this).height;
  }

  EdgeInsets get viewPadding {
    return MediaQuery.viewPaddingOf(this);
  }

  EdgeInsets get viewInsets {
    return MediaQuery.viewInsetsOf(this);
  }

  bool get isKeyboardVisible {
    return MediaQuery.viewInsetsOf(this).bottom > 0;
  }
}
