import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/commission/settlement_batch_data.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final commissionSettlementDataProvider = FutureProvider.autoDispose
    .family<R<SettlementBatchData>, List<String>>((ref, status) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.fetchBatchSettlement(status);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
