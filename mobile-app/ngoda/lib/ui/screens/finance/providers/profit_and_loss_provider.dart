import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/financial-statements/profit-and-loss/profit_and_loss.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final profitAndLossProvider = FutureProvider.autoDispose
    .family<R<ProfitAndLoss>, FinancialStatementParams>((ref, params) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.fetchProfitnLoss(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
