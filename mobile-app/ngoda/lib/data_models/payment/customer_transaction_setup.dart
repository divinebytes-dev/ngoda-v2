import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/customer/loan_summary.dart';

class CustomerTransactionSetup {
  CustomerTransactionSetup({
    required this.currencyRegistry,
    required this.loanSummary,
    required Map<String, double> balances,
  }) : balances = Map.unmodifiable(
         balances.map(
           (currency, balance) =>
               MapEntry(currency.trim().toLowerCase(), balance),
         ),
       );

  final CurrencyRegistry currencyRegistry;

  final LoanSummary loanSummary;

  final Map<String, double> balances;

  double? balanceFor(String currency) {
    return balances[currency.trim().toLowerCase()];
  }

  bool hasBalanceFor(String currency) {
    return balances.containsKey(currency.trim().toLowerCase());
  }

  List<String> get currencies {
    return List.unmodifiable(balances.keys);
  }
}
