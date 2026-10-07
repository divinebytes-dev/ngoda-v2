import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/params/wallet_snapshot_params.dart';
import 'package:ngoda/data_models/wallet/wallet_periodic_balance.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service_provider.dart';

final walletBalanceSnapshotProvider = FutureProvider.autoDispose
    .family<R<WalletBalancePeriod>, WalletSnapshotParams>((ref, params) async {
      try {
        final api = ref.read(miniStatementApiServiceProvider);

        final response = await api.getWalletBalanceSnapshot(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
