import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/loan/liquidation/liquidated_loans_today.dart';
import 'package:ngoda/data_models/params/loan_liquidation_params.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final liquidatedLoansProvider = FutureProvider.autoDispose
    .family<R<LiquidatedLoansToday>, LoanLiquidationParams>((
      ref,
      params,
    ) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.fetchLiquidatedLoans(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
