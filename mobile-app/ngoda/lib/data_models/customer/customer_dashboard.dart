import 'package:ngoda/data_models/blockchain/blockchain_wallet_balance.dart';
import 'package:ngoda/data_models/gamification/loyalty/loyalty.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/customer/loan_summary.dart';
import 'package:ngoda/data_models/wallet/wallet.dart';

class CustomerDashboard {
  CustomerDashboard({
    required this.loyalty,
    required this.wallet,
    required this.loanSummary,
    required List<Currency> currencies,
    required this.currencyRegistry,
    required List<BlockchainWalletBalance> blockchainBalances,
  }) : currencies = List.unmodifiable(currencies),
       blockchainBalances = List.unmodifiable(blockchainBalances);

  final Loyalty loyalty;
  final Wallet wallet;
  final LoanSummary loanSummary;

  final List<Currency> currencies;
  final CurrencyRegistry currencyRegistry;

  final List<BlockchainWalletBalance> blockchainBalances;

  factory CustomerDashboard.fromJson({
    required Map<String, dynamic> loyaltyJson,
    required Map<String, dynamic> walletJson,
    required Map<String, dynamic> loanSummary,
    required List<Currency> currencies,
    required CurrencyRegistry currencyRegistry,
  }) {
    final rawBlockchainBalances = walletJson['blockchains'];

    final blockchainBalances = rawBlockchainBalances is List
        ? rawBlockchainBalances
              .whereType<Map<String, dynamic>>()
              .map(BlockchainWalletBalance.fromJson)
              .toList()
        : <BlockchainWalletBalance>[];

    return CustomerDashboard(
      loyalty: Loyalty.fromJson(loyaltyJson),
      wallet: Wallet.fromJson(walletJson),
      loanSummary: LoanSummary.fromJson(loanSummary),
      currencies: currencies,
      currencyRegistry: currencyRegistry,
      blockchainBalances: blockchainBalances,
    );
  }

  Currency? currency(String currencyCode) {
    return currencyRegistry.getByCode(currencyCode);
  }

  bool supportsCurrency(String currencyCode) {
    return currencyRegistry.contains(currencyCode);
  }

  List<BlockchainWalletBalance> balancesForBlockchain(String blockchainCode) {
    final code = blockchainCode.trim().toLowerCase();

    return blockchainBalances
        .where((balance) => balance.blockchainCode == code)
        .toList(growable: false);
  }

  List<BlockchainWalletBalance> balancesForCurrency(String currencyCode) {
    final code = currencyCode.trim().toLowerCase();

    return blockchainBalances
        .where((balance) => balance.currencyCode == code)
        .toList(growable: false);
  }
}
