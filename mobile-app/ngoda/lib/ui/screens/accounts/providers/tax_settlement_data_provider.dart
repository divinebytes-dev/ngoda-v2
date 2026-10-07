import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/tax/tax_settlement_batch_data.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final taxSettlementDataProvider = FutureProvider.family
    .autoDispose<R<TaxSettlementBatchData>, List<String>>((ref, status) async {
      try {
        final api = ref.read(financeApiServiceProvider);
        final response = await api.fetchTaxSettlementData(status);
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
