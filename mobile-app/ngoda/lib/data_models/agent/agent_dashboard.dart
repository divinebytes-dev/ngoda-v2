import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/customer/loan_summary.dart';
import 'package:ngoda/data_models/transaction/daily_transaction_summary.dart';
import 'package:ngoda/data_models/wallet/wallet.dart';
import 'package:ngoda/services/currency_service.dart';

class AgentDashboard {
  AgentDashboard({
    required this.agentWallet,
    required this.customerWallet,
    required this.loanSummary,
    required this.dailySummary,
    required List<Currency> currencies,
    required this.currencyRegistry,
  }) : currencies = List.unmodifiable(currencies);

  final Wallet agentWallet;
  final Wallet customerWallet;
  final LoanSummary loanSummary;
  final DailyTransactionSummary dailySummary;

  final List<Currency> currencies;
  final CurrencyRegistry currencyRegistry;

  factory AgentDashboard.fromJson({
    required Map<String, dynamic> agentWalletJson,
    required Map<String, dynamic> customerWalletJson,
    required Map<String, dynamic> loanSummaryJson,
    required Map<String, dynamic> dailySummaryJson,
    required List<dynamic> currencyList,
  }) {
    final currencies = currencyList
        .whereType<Map>()
        .map(
          (currency) => Currency.fromJson(Map<String, dynamic>.from(currency)),
        )
        .toList();

    CurrencyService.initialize(currencies);
    return AgentDashboard(
      agentWallet: Wallet.fromJson(agentWalletJson),
      customerWallet: Wallet.fromJson(customerWalletJson),
      loanSummary: LoanSummary.fromJson(loanSummaryJson),
      dailySummary: DailyTransactionSummary.fromJson(dailySummaryJson),
      currencies: currencies,
      currencyRegistry: CurrencyRegistry.fromCurrencies(currencies),
    );
  }

  Currency? currency(String currencyCode) {
    return currencyRegistry.getByCode(currencyCode);
  }

  bool supportsCurrency(String currencyCode) {
    return currencyRegistry.contains(currencyCode);
  }
}
