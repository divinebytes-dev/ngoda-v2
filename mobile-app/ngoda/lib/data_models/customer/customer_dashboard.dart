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
  }) : currencies = List.unmodifiable(currencies);

  final Loyalty loyalty;
  final Wallet wallet;
  final LoanSummary loanSummary;

  final List<Currency> currencies;
  final CurrencyRegistry currencyRegistry;

  factory CustomerDashboard.fromJson({
    required Map<String, dynamic> loyaltyJson,
    required Map<String, dynamic> walletJson,
    required Map<String, dynamic> loanSummary,
    required List<Currency> currencies,
    required CurrencyRegistry currencyRegistry,
  }) {
    return CustomerDashboard(
      loyalty: Loyalty.fromJson(loyaltyJson),
      wallet: Wallet.fromJson(walletJson),
      loanSummary: LoanSummary.fromJson(loanSummary),
      currencies: currencies,
      currencyRegistry: currencyRegistry,
    );
  }

  Currency? currency(String currencyCode) {
    return currencyRegistry.getByCode(currencyCode);
  }

  bool supportsCurrency(String currencyCode) {
    return currencyRegistry.contains(currencyCode);
  }
}
