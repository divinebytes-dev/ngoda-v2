import 'package:flutter_riverpod/flutter_riverpod.dart';

class NfcSupportedNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void setSupported(bool supported) {
    state = supported;
  }

  void reset() {
    state = false;
  }
}

final nfcSupportedProvider = NotifierProvider<NfcSupportedNotifier, bool>(
  NfcSupportedNotifier.new,
);
