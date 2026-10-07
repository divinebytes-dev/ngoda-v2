import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/fee/transaction_config.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final transactionsConfigProvider = FutureProvider<R<TransactionConfig>>((
  ref,
) async {
  try {
    final api = ref.read(financeApiServiceProvider);
    final response = await api.fetchTransactionsConfig();
    return R(result: response);
  } catch (err) {
    return R(error: err.toString());
  }
});
