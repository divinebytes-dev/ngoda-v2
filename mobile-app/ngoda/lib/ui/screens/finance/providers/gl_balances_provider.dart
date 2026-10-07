import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/gl/gl_balance_summary.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final glBalancesProvider = FutureProvider.autoDispose<R<GLBalanceSummary>>((
  ref,
) async {
  try {
    final api = ref.read(financeApiServiceProvider);

    final response = await api.fetchGlBalances();

    return R(result: response);
  } catch (error) {
    return R(error: error.toString());
  }
});
