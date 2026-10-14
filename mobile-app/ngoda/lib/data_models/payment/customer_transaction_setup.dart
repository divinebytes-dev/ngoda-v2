import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/customer/loan_summary.dart';

class CustomerTransactionSetup {
  CustomerTransactionSetup({
    required this.currencyRegistry,
    required this.loanSummary,
    required Map<String, double> balances,
    Map<String, double> blockchainBalances = const {},
  }) : balances = Map.unmodifiable(
         balances.map(
           (currency, balance) =>
               MapEntry(currency.trim().toLowerCase(), balance),
         ),
       ),
       blockchainBalances = Map.unmodifiable(
         blockchainBalances.map(
           (blockchain, balance) =>
               MapEntry(blockchain.trim().toLowerCase(), balance),
         ),
       );

  final CurrencyRegistry currencyRegistry;

  final LoanSummary loanSummary;

  /// Existing currency balances.
  ///
  /// Used by fiat transactions.
  final Map<String, double> balances;

  /// Customer GOLD balances by blockchain code.
  ///
  /// Example:
  /// {
  ///   'gnosis': 0.548321,
  ///   'polygon': 1.250000,
  /// }
  final Map<String, double> blockchainBalances;

  double? balanceFor(String currency) {
    return balances[currency.trim().toLowerCase()];
  }

  bool hasBalanceFor(String currency) {
    return balances.containsKey(currency.trim().toLowerCase());
  }

  /// Returns the customer's GOLD balance
  /// on the selected blockchain.
  double? goldBalanceFor(String blockchainCode) {
    return blockchainBalances[blockchainCode.trim().toLowerCase()];
  }

  bool hasGoldBalanceFor(String blockchainCode) {
    return blockchainBalances.containsKey(blockchainCode.trim().toLowerCase());
  }

  /// Available blockchain codes.
  List<String> get blockchains {
    final codes = blockchainBalances.keys.toList()..sort();
    return List.unmodifiable(codes);
  }

  List<String> get currencies {
    return List.unmodifiable(balances.keys);
  }
}
