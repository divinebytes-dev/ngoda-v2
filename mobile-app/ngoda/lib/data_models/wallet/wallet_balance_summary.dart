import 'package:ngoda/data_models/blockchain/blockchain_wallet_balance.dart';
import 'package:ngoda/data_models/wallet/wallet.dart';

class WalletBalanceSummary {
  WalletBalanceSummary({
    required this.walletBalances,
    required List<BlockchainWalletBalance> blockchainBalances,
  }) : blockchainBalances = List.unmodifiable(blockchainBalances);

  final Wallet walletBalances;
  final List<BlockchainWalletBalance> blockchainBalances;

  factory WalletBalanceSummary.fromJson(Map<String, dynamic> json) {
    final rawBlockchainBalances = json['blockchain_balances'];

    print("jsob $json");
    final blockchainBalances = <BlockchainWalletBalance>[];

    if (rawBlockchainBalances is List) {
      for (final item in rawBlockchainBalances) {
        if (item is! Map) {
          continue;
        }

        blockchainBalances.add(
          BlockchainWalletBalance.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    }

    return WalletBalanceSummary(
      walletBalances: Wallet.fromJson({
        'balances': json['balances'] ?? <String, dynamic>{},
      }),
      blockchainBalances: blockchainBalances,
    );
  }

  factory WalletBalanceSummary.empty() {
    return WalletBalanceSummary(
      walletBalances: Wallet.empty(),
      blockchainBalances: const [],
    );
  }

  bool get isEmpty => walletBalances.isEmpty;

  bool get isNotEmpty => walletBalances.isNotEmpty;
}

extension WalletBalanceSummaryX on WalletBalanceSummary {
  double get totalUsdValue => walletBalances.totalUsdValue;

  List<String> get currencyList => walletBalances.currencyList;

  List<String> get sortedCurrencyList => walletBalances.sortedCurrencyList;

  int get blockchainCount => blockchainBalances.length;

  bool get hasBlockchainBalances => blockchainBalances.isNotEmpty;

  List<BlockchainWalletBalance> getBlockchainBalances(String blockchainCode) {
    final code = blockchainCode.trim().toLowerCase();

    return List.unmodifiable(
      blockchainBalances.where((balance) => balance.blockchainCode == code),
    );
  }

  BlockchainWalletBalance? getBlockchainCurrencyBalance({
    required String blockchainCode,
    required String currencyCode,
  }) {
    final chain = blockchainCode.trim().toLowerCase();
    final currency = currencyCode.trim().toLowerCase();

    for (final balance in blockchainBalances) {
      if (balance.blockchainCode == chain && balance.currencyCode == currency) {
        return balance;
      }
    }

    return null;
  }
}

// import 'package:ngoda/data_models/wallet/wallet.dart';

// class WalletBalanceSummary {
//   const WalletBalanceSummary({required this.walletBalances});

//   final Wallet walletBalances;

//   factory WalletBalanceSummary.fromJson(Map<String, dynamic> json) {
//     return WalletBalanceSummary(
//       walletBalances: Wallet.fromJson({
//         'balances': json['balances'] ?? <String, dynamic>{},
//       }),
//     );
//   }

//   factory WalletBalanceSummary.empty() {
//     return WalletBalanceSummary(walletBalances: Wallet.empty());
//   }

//   bool get isEmpty => walletBalances.isEmpty;

//   bool get isNotEmpty => walletBalances.isNotEmpty;
// }

// extension WalletBalanceSummaryX on WalletBalanceSummary {
//   double get totalUsdValue => walletBalances.totalUsdValue;

//   List<String> get currencyList => walletBalances.currencyList;

//   List<String> get sortedCurrencyList => walletBalances.sortedCurrencyList;
// }
