import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/params/wallet_entry_params.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_drilldown.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service_provider.dart';

final walletPeriodicBalancesProvider = FutureProvider.autoDispose
    .family<R<PeriodicBalanceDrilldown>, WalletEntryParams>((
      ref,
      params,
    ) async {
      try {
        final api = ref.read(miniStatementApiServiceProvider);

        final response = await api.getPeriodicWalletEntries(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
