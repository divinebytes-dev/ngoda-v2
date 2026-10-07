import 'package:ngoda/data_models/gamification/badges/loyalty_badge_collection.dart';
import 'package:ngoda/data_models/gamification/ledger/loyalty_ledger_page.dart';
import 'package:ngoda/data_models/gamification/loyalty/loyalty_summary.dart';
import 'package:ngoda/data_models/gamification/notifications/acknowledge_gamification_notification_result.dart';
import 'package:ngoda/data_models/gamification/notifications/gamification_notification_feed.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GamificationApiService {
  const GamificationApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<LoyaltySummary> fetchLoyaltySummary() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-loyalty-summary',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid loyalty summary response',
    );

    return LoyaltySummary.fromJson(data);
  }

  Future<LoyaltyLedgerPage> fetchLoyaltyLedger({
    int page = 1,
    int pageSize = 50,
  }) async {
    if (page < 1) {
      throw ArgumentError.value(
        page,
        'page',
        'Page must be greater than zero.',
      );
    }

    if (pageSize < 1) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Page size must be greater than zero.',
      );
    }

    final data = await _functions.invokeData(
      functionName: 'fetch-loyalty-ledger',
      method: HttpMethod.get,
      queryParameters: {'page': page, 'pageSize': pageSize},
      invalidResponseMessage: 'Invalid loyalty ledger response',
    );

    return LoyaltyLedgerPage.fromJson(data);
  }

  Future<LoyaltyBadgeCollection> fetchLoyaltyBadges() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-loyalty-badges',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid loyalty badges response',
    );

    return LoyaltyBadgeCollection.fromJson(data);
  }

  Future<GamificationNotificationFeed> fetchGamificationNotifications({
    int limit = 20,
  }) async {
    if (limit < 1) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Limit must be greater than zero.',
      );
    }

    final data = await _functions.invokeData(
      functionName: 'fetch-gamification-notifications',
      method: HttpMethod.get,
      queryParameters: {'limit': limit},
      invalidResponseMessage: 'Invalid gamification notifications response',
    );

    return GamificationNotificationFeed.fromJson(data);
  }

  Future<AcknowledgeGamificationNotificationResult>
  acknowledgeGamificationNotification({
    required String notificationId,
    bool markSeen = false,
  }) async {
    final id = notificationId.trim();

    if (id.isEmpty) {
      throw ArgumentError.value(
        notificationId,
        'notificationId',
        'Notification ID cannot be empty.',
      );
    }

    final data = await _functions.invokeData(
      functionName: 'acknowledge-gamification-notification',
      method: HttpMethod.post,
      body: {'notification_id': id, 'mark_seen': markSeen},
      invalidResponseMessage: 'Invalid gamification acknowledgement response',
    );

    return AcknowledgeGamificationNotificationResult.fromJson(data);
  }
}
