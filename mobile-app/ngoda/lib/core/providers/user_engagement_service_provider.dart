import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/core/providers/notification_service_provider.dart';
import 'package:ngoda/services/user_engagement_service.dart';

final userEngagementServiceProvider = Provider<UserEngagementService>((ref) {
  return UserEngagementService(
    hive: ref.watch(hiveServiceProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});
