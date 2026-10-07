import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/core/providers/crashlytics_service_provider.dart';
import 'package:ngoda/services/analytics_service.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final crashlyticsService = ref.watch(crashlyticsServiceProvider);

  return AnalyticsService(crashlyticsService);
});
