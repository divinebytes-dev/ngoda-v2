import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/transaction/transaction_v.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final transactionVProvider = FutureProvider<R<TransactionV>>((ref) async {
  try {
    final api = ref.read(financeApiServiceProvider);
    final response = await api.fetchTransactionV();
    return R(result: response);
  } catch (err) {
    return R(error: err.toString());
  }
});
