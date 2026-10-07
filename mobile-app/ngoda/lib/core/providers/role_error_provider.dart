import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoleErrorShownNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void markShown() {
    state = true;
  }

  void reset() {
    state = false;
  }
}

final roleErrorShownProvider = NotifierProvider<RoleErrorShownNotifier, bool>(
  RoleErrorShownNotifier.new,
);
