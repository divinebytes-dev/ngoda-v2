import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/params/settlement_items_params.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/tax/tax_settlement_items_page.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final taxSettlementItemsProvider = FutureProvider.autoDispose
    .family<R<TaxSettlementItemsPage>, SettlementItemsParams>((
      ref,
      params,
    ) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.fetchTaxSettlementItems(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
