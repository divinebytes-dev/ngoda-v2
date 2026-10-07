import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/finance/finance_transaction_summary.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final recentTransactionsProvider = FutureProvider.autoDispose
    .family<R<FinanceTransactionSummary>, FinancialStatementParams>((
      ref,
      params,
    ) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.getRecentTransactions(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
