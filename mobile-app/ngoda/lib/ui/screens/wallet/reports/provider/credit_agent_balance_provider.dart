import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/merchant/credit_agent_balance_report.dart';
import 'package:ngoda/data_models/params/credit_agent_balance_params.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service_provider.dart';

final creditAgentBalanceProvider = FutureProvider.autoDispose
    .family<R<CreditAgentBalanceReport>, CreditAgentBalanceParams>((
      ref,
      params,
    ) async {
      try {
        final api = ref.read(miniStatementApiServiceProvider);

        final response = await api.getCreditAgentsBalances(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
