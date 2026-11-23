import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/params/tax_entry_params.dart';
import 'package:ngoda/data_models/reserve-bank/tax_period_drilldown.dart';
import 'package:ngoda/ui/screens/reserve-bank/services/reserve_bank_api_service_provider.dart';

final taxPeriodicEntriesProvider = FutureProvider.autoDispose
    .family<R<TaxPeriodDrilldown>, TaxEntryParams>((ref, params) async {
      try {
        final api = ref.read(reserveBankApiServiceProvider);

        final response = await api.fetchPeriodicTaxEntries(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
