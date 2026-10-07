import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/merchant/credit_agent_balance_drilldown.dart';
import 'package:ngoda/data_models/params/credit_agent_balance_params.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service_provider.dart';

final creditAgentBalanceDrilldownProvider = FutureProvider.autoDispose
    .family<R<CreditAgentBalanceDrilldown>, CreditAgentBalanceParams>((
      ref,
      params,
    ) async {
      try {
        final api = ref.read(miniStatementApiServiceProvider);

        final response = await api.getCreditAgentBalanceDrilldown(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
