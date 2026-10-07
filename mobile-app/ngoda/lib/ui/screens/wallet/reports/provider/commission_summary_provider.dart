import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/agent/commission_summary.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service_provider.dart';

final commissionSummaryProvider =
    FutureProvider.autoDispose<R<CommissionSummary>>((ref) async {
      try {
        final api = ref.read(miniStatementApiServiceProvider);

        final response = await api.fetchCommissionSummary();

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
