import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/treasury/treasury_balances.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_api_service_provider.dart';

final walletSnapshotProvider = FutureProvider<R<TreasuryBalances>>((ref) async {
  try {
    final api = ref.read(treasuryApiServiceProvider);

    final response = await api.fetchWalletBalanceSnapshot();

    return R(result: response);
  } catch (error) {
    return R(error: error.toString());
  }
});
