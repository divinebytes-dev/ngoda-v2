import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/commission/settlement_items_page.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final commissionSettlementItemsProvider = FutureProvider.autoDispose
    .family<R<SettlementItemsPage>, SettlementItemsParams>((ref, params) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.fetchBatchSettlementItems(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
