import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/gamification/badges/loyalty_badge_collection.dart';
import 'package:ngoda/ui/screens/gamification/services/gamification_api_service_provider.dart';

final loyaltyBadgesProvider =
    FutureProvider.autoDispose<R<LoyaltyBadgeCollection>>((ref) async {
      try {
        final api = ref.read(gamificationApiServiceProvider);

        final response = await api.fetchLoyaltyBadges();

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
