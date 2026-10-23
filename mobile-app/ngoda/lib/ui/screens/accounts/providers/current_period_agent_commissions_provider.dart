import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/params/current_commission_params.dart';
import 'package:ngoda/data_models/commission/current_period_agent_commissions.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final currentPeriodAgentCommissionsProvider = FutureProvider.family
    .autoDispose<R<CurrentPeriodAgentCommissions>, CurrentCommissionParams>((ref, params) async {
      try {
        final api = ref.read(financeApiServiceProvider);
        final response = await api.fetchCurrentPeriodAgentCommissions(params);
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
