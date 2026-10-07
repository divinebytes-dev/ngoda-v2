import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final trialBalanceProvider = FutureProvider.autoDispose
    .family<R<TrialBalance>, FinancialStatementParams>((ref, params) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.fetchTrialBalance(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
