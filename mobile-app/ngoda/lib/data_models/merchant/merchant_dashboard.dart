import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/merchant/credit_agent_currency_balance.dart';
import 'package:ngoda/data_models/transaction/daily_transaction_summary.dart';
import 'package:ngoda/data_models/wallet/wallet.dart';
import 'package:ngoda/services/currency_service.dart';

class MerchantDashboard {
  MerchantDashboard({
    required this.agentWallet,
    required this.merchantWallet,
    required this.dailySummary,
    required List<Currency> currencies,
    required this.currencyRegistry,
    required this.isCreditAgent,
    required this.creditAgent,
  }) : currencies = List.unmodifiable(currencies);

  final bool isCreditAgent;

  final CreditAgentWallet creditAgent;

  final Wallet agentWallet;
  final Wallet merchantWallet;

  final DailyTransactionSummary dailySummary;

  final List<Currency> currencies;

  final CurrencyRegistry currencyRegistry;

  factory MerchantDashboard.fromJson({
    required Map<String, dynamic> agentWalletJson,
    required Map<String, dynamic> merchantWalletJson,
    required Map<String, dynamic> dailySummaryJson,
    required List<dynamic> currencies,
    required bool isCreditAgent,
    required Map<String, dynamic> creditAgentJson,
  }) {
    final parsedCurrencies = currencies
        .whereType<Map>()
        .map(
          (currency) => Currency.fromJson(Map<String, dynamic>.from(currency)),
        )
        .toList();

    CurrencyService.initialize(parsedCurrencies);
    return MerchantDashboard(
      agentWallet: Wallet.fromJson(agentWalletJson),
      merchantWallet: Wallet.fromJson(merchantWalletJson),
      dailySummary: DailyTransactionSummary.fromJson(dailySummaryJson),
      currencies: parsedCurrencies,
      currencyRegistry: CurrencyRegistry.fromCurrencies(parsedCurrencies),
      isCreditAgent: isCreditAgent,
      creditAgent: CreditAgentWallet.fromJson(creditAgentJson),
    );
  }
}
