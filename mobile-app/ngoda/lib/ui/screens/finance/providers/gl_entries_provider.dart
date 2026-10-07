import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/params/gl_entry_params.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_drilldown.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final glEntriesProvider = FutureProvider.autoDispose
    .family<R<PeriodicBalanceDrilldown>, GlEntryParams>((ref, params) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.fetchGlEntries(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
