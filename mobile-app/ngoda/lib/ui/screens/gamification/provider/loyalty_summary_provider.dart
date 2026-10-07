import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/gamification/loyalty/loyalty_summary.dart';
import 'package:ngoda/ui/screens/gamification/services/gamification_api_service_provider.dart';

final loyaltySummaryProvider = FutureProvider.autoDispose<R<LoyaltySummary>>((
  ref,
) async {
  try {
    final api = ref.read(gamificationApiServiceProvider);

    final response = await api.fetchLoyaltySummary();

    return R(result: response);
  } catch (error) {
    return R(error: error.toString());
  }
});
