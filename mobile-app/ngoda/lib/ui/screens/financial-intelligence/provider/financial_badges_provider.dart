import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/financial-intelligence/badges/financial_badge_list.dart';
import 'package:ngoda/ui/screens/financial-intelligence/services/financial_service_api_service_provider.dart';

final financialBadgesProvider =
    FutureProvider.autoDispose<R<FinancialBadgeList>>((ref) async {
      try {
        final api = ref.read(financialIntelligenceApiServiceProvider);

        final response = await api.getFinancialBadges();

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
