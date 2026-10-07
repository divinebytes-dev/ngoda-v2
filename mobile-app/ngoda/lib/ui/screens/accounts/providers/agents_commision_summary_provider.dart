import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/commission/agents_commission_summary.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_api_service_provider.dart';

final agentsCommissionSummaryProvider =
    FutureProvider.autoDispose<R<AgentsCommissionSummary>>((ref) async {
      try {
        final api = ref.read(accountsApiServiceProvider);
        final response = await api.fetchAgentsCommissionSummary();
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
