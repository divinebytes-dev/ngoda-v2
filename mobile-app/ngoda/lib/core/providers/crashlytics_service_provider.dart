import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/services/crashlytics_service.dart';

final crashlyticsServiceProvider = Provider<CrashlyticsService>((ref) {
  return CrashlyticsService();
});
