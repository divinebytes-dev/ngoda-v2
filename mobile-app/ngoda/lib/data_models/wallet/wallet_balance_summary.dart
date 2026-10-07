import 'package:ngoda/data_models/wallet/wallet.dart';

class WalletBalanceSummary {
  const WalletBalanceSummary({required this.walletBalances});

  final Wallet walletBalances;

  factory WalletBalanceSummary.fromJson(Map<String, dynamic> json) {
    return WalletBalanceSummary(
      walletBalances: Wallet.fromJson({
        'balances': json['balances'] ?? <String, dynamic>{},
      }),
    );
  }

  factory WalletBalanceSummary.empty() {
    return WalletBalanceSummary(walletBalances: Wallet.empty());
  }

  bool get isEmpty => walletBalances.isEmpty;

  bool get isNotEmpty => walletBalances.isNotEmpty;
}

extension WalletBalanceSummaryX on WalletBalanceSummary {
  double get totalUsdValue => walletBalances.totalUsdValue;

  List<String> get currencyList => walletBalances.currencyList;

  List<String> get sortedCurrencyList => walletBalances.sortedCurrencyList;
}
