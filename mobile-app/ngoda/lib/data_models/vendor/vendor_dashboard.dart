import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/customer/loan_summary.dart';
import 'package:ngoda/data_models/transaction/daily_transaction_summary.dart';
import 'package:ngoda/data_models/wallet/wallet.dart';
import 'package:ngoda/services/currency_service.dart';

class VendorDashboard {
  VendorDashboard({
    required this.agentWallet,
    required this.customerWallet,
    required this.merchantWallet,
    required this.loanSummary,
    required this.dailySummary,
    required List<Currency> currencies,
    required this.currencyRegistry,
  }) : currencies = List.unmodifiable(currencies);

  final Wallet agentWallet;
  final Wallet customerWallet;
  final Wallet merchantWallet;

  final LoanSummary loanSummary;

  final DailyTransactionSummary dailySummary;

  final List<Currency> currencies;

  final CurrencyRegistry currencyRegistry;

  factory VendorDashboard.fromJson({
    required Map<String, dynamic> agentWalletJson,
    required Map<String, dynamic> customerWalletJson,
    required Map<String, dynamic> merchantWalletJson,
    required Map<String, dynamic> loanSummaryJson,
    required Map<String, dynamic> dailySummaryJson,
    required List<dynamic> currencies,
  }) {
    final parsedCurrencies = currencies
        .whereType<Map>()
        .map(
          (currency) => Currency.fromJson(Map<String, dynamic>.from(currency)),
        )
        .toList();
    /*
       * CurrencyService is the application-level currency
       * lookup used by services such as NumberFormatService.
       *
       * Each dashboard receives its supported currencies
       * from the backend, so loading the dashboard refreshes
       * the currency lookup for the current user/context.
       */
    CurrencyService.initialize(parsedCurrencies);
    return VendorDashboard(
      agentWallet: Wallet.fromJson(agentWalletJson),
      customerWallet: Wallet.fromJson(customerWalletJson),
      merchantWallet: Wallet.fromJson(merchantWalletJson),
      loanSummary: LoanSummary.fromJson(loanSummaryJson),
      dailySummary: DailyTransactionSummary.fromJson(dailySummaryJson),
      currencies: parsedCurrencies,
      currencyRegistry: CurrencyRegistry.fromCurrencies(parsedCurrencies),
    );
  }
}
