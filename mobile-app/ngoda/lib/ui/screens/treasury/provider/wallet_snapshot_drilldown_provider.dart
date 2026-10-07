import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/wallet/wallet_balance_snapshot_drill.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_api_service_provider.dart';

final walletSnapshotDrilldownProvider =
    FutureProvider.family<R<WalletBalanceSnapshotDrill>, String>((
      ref,
      currency,
    ) async {
      try {
        final api = ref.read(treasuryApiServiceProvider);

        final response = await api.fetchWalletBalanceSnapshotDrilldown(
          currency,
        );

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
